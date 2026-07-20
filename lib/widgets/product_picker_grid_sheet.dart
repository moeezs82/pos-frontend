import 'dart:async';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:flutter/services.dart';

/// ✅ Full-screen restaurant-style product picker (Grid + multi select + preselected + SET qty modal)
/// Multi returns:
///   List<Map<String,dynamic>>: [ { "product": <productMap>, "qty": 3.0 }, ... ]
/// Single returns:
///   Map<String,dynamic> product
class ProductPickerGridSheet extends StatefulWidget {
  final String token;
  final int? vendorId;

  /// If true -> returns List<{product, qty}>, else -> returns single product map
  final bool multi;

  /// already selected ids
  final List<int> alreadySelectedIds;

  /// optional already selected product maps
  final List<Map<String, dynamic>> alreadySelectedProducts;

  /// optional already selected qty map (id -> qty)
  final Map<int, double> alreadySelectedQty;

  const ProductPickerGridSheet({
    super.key,
    required this.token,
    this.vendorId,
    this.multi = true,
    this.alreadySelectedIds = const [],
    this.alreadySelectedProducts = const [],
    this.alreadySelectedQty = const {},
  });

  /// ✅ Use this instead of showModalBottomSheet for FULL SCREEN
  static Future<List<Map<String, dynamic>>?> openMulti(
    BuildContext context, {
    required String token,
    int? vendorId,
    List<int> alreadySelectedIds = const [],
    Map<int, double> alreadySelectedQty = const {},
    List<Map<String, dynamic>> alreadySelectedProducts = const [],
  }) {
    return showGeneralDialog<List<Map<String, dynamic>>?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "ProductPicker",
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        return Material(
          child: ProductPickerGridSheet(
            token: token,
            vendorId: vendorId,
            multi: true,
            alreadySelectedIds: alreadySelectedIds,
            alreadySelectedQty: alreadySelectedQty,
            alreadySelectedProducts: alreadySelectedProducts,
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<ProductPickerGridSheet> createState() => _ProductPickerGridSheetState();
}

class _ProductPickerGridSheetState extends State<ProductPickerGridSheet> {
  late final ProductService _productService;

  final List<Map<String, dynamic>> _products = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false; // only true blocking case: zero cache on first ever open
  bool _silentRefreshing = false;

  String _search = "";
  Timer? _debounce;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  /// selection ids
  final Set<int> _selectedIds = <int>{};

  /// selected product cache
  final Map<int, Map<String, dynamic>> _selectedMapById = {};

  /// qty per selected product
  final Map<int, double> _qtyById = {};

  String get _cacheKey => ProductPickCache.keyFor(vendorId: widget.vendorId);

  @override
  void initState() {
    super.initState();
    _productService = ProductService(token: widget.token);

    // prefill ids
    _selectedIds.addAll(widget.alreadySelectedIds);

    // prefill qty
    for (final e in widget.alreadySelectedQty.entries) {
      final id = e.key;
      final qty = e.value == 0 ? 1.0 : e.value;
      _selectedIds.add(id);
      _qtyById[id] = qty;
    }

    // ensure ids have qty
    for (final id in widget.alreadySelectedIds) {
      _qtyById[id] = _qtyById[id] ?? 1.0;
    }

    // prefill maps
    for (final p in widget.alreadySelectedProducts) {
      final id = _asInt(p['id']);
      if (id != null) {
        _selectedIds.add(id);
        _selectedMapById[id] = p;
        _qtyById[id] = _qtyById[id] ?? 1.0;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });

    // Cache-first: paint whatever's cached for this vendor scope instantly
    // (likely warmed by a prefetch when the sale/purchase screen opened),
    // then always silently re-check in the background.
    final cached = ProductPickCache.cache.peek(_cacheKey);
    if (cached != null) {
      _products.addAll(cached.items);
      _page = cached.currentPage;
      _lastPage = cached.lastPage;
      for (final p in cached.items) {
        final id = _asInt(p['id']);
        if (id != null && _selectedIds.contains(id)) {
          _selectedMapById[id] = p;
          _qtyById[id] = _qtyById[id] ?? 1.0;
        }
      }
    }
    _fetchProducts(page: 1, replace: true, silent: cached != null);

    // Enter (confirm) / Escape (close) need to work no matter what currently
    // has focus — the search box, a focused grid card, or nothing at all.
    // CallbackShortcuts/Shortcuts only fires when no *closer* widget already
    // claims the key (the search TextField eats Enter for its own
    // onSubmitted, for example), so we listen at the hardware level instead,
    // which always sees the key regardless of focus.
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  /// Returns true to mark the key event as handled (swallowed), false to let
  /// it pass through to whatever would normally receive it (typing in the
  /// search box, etc).
  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    // Don't act if a dialog (e.g. the qty-set prompt) is showing above this
    // screen — let that dialog's own Enter/Escape handling take over.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return true;
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_selectedIds.isNotEmpty) {
        Navigator.of(context).pop(_pickedWithQty());
      } else {
        // Nothing selected yet — treat Enter as "run the search" instead,
        // same as pressing Enter in the search box used to do.
        _fetchProducts(page: 1, replace: true);
      }
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String _money(dynamic v) => AppCurrency.format(v);
  String _name(dynamic v) => (v ?? "Unnamed").toString();

  String? _imageUrl(Map<String, dynamic> p) {
    final url = p['image_url'] ?? p['image'] ?? p['thumbnail'] ?? p['photo'];
    if (url == null) return null;
    final s = url.toString().trim();
    return s.isEmpty ? null : s;
  }

  double _qtyOf(int id) => _qtyById[id] ?? 1.0;

  void _selectDefault(Map<String, dynamic> p) {
    final id = _asInt(p['id']);
    if (id == null) return;
    setState(() {
      _selectedIds.add(id);
      _selectedMapById[id] = p;
      _qtyById[id] = _qtyById[id] ?? 1.0;
    });
  }

  void _setQty(int id, double qty) {
    setState(() {
      _qtyById[id] = qty == 0 ? 1.0 : qty;
    });
  }

  void _unselect(int id) {
    setState(() {
      _selectedIds.remove(id);
      _selectedMapById.remove(id);
      _qtyById.remove(id);
    });
  }

  // ---------- data ----------
  Future<void> _fetchProducts({required int page, bool replace = true, bool silent = false}) async {
    if (silent) {
      setState(() => _silentRefreshing = true);
    } else {
      if (_loading) return;
      setState(() => _loading = true);
    }

    try {
      final entry = _search.isEmpty
          // Unfiltered fetch — safe to store in the shared bucket that
          // other screens read via peek() (e.g. before a vendor is even
          // picked in a sale, the unfiltered product list is prefetched).
          ? await ProductPickCache.cache.refresh(
              _cacheKey,
              () => ProductPickCache.fetchPage(
                _productService,
                page: page,
                search: _search,
                vendorId: widget.vendorId,
                perPage: 100,
              ),
              requestKey: '$_cacheKey::$_search::$page',
            )
          // Filtered (search) fetch — must not overwrite the shared
          // bucket. Apply locally to this sheet only.
          : await ProductPickCache.fetchPage(
              _productService,
              page: page,
              search: _search,
              vendorId: widget.vendorId,
              perPage: 100,
            );

      final newProducts = entry.items;

      // update cache if selected appears
      for (final p in newProducts) {
        final id = _asInt(p['id']);
        if (id != null && _selectedIds.contains(id)) {
          _selectedMapById[id] = p;
          _qtyById[id] = _qtyById[id] ?? 1.0;
        }
      }

      if (!mounted) return;
      setState(() {
        if (replace) {
          _products
            ..clear()
            ..addAll(newProducts);
        } else {
          _products.addAll(newProducts);
        }
        _page = entry.currentPage;
        _lastPage = entry.lastPage;
      });
    } catch (_) {
      // Silent refresh failures stay quiet; keep whatever was on screen.
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _silentRefreshing = false;
      });
    }
  }

  void _onSearchChanged(String val) {
    final query = val.trim();

    // Instant local filter against the cached page for this vendor scope —
    // covers the common "type a few letters of the item name" case with
    // zero network wait.
    final cached = ProductPickCache.cache.peek(_cacheKey);
    if (cached != null) {
      final q = query.toLowerCase();
      final filtered = q.isEmpty
          ? cached.items
          : cached.items.where((p) {
              final name = (p['name'] ?? '').toString().toLowerCase();
              final sku = (p['sku'] ?? p['barcode'] ?? '').toString().toLowerCase();
              return name.contains(q) || sku.contains(q);
            }).toList();
      setState(() {
        _products
          ..clear()
          ..addAll(filtered);
      });
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _search = val.trim());
      _fetchProducts(page: 1, replace: true, silent: cached != null);
    });
  }

  // ---------- qty modal (SET qty) ----------
  Future<void> _promptSetQty(Map<String, dynamic> p) async {
    final id = _asInt(p['id']);
    if (id == null) return;

    // ensure selected
    _selectDefault(p);

    final ctrl = TextEditingController(text: _qtyOf(id).toStringAsFixed(0));

    final newQty = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_name(p['name'])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Quantity"),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                hintText: "e.g. 3 or -1",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Use negative quantity for exchange/return adjustment. Enter 0 to remove the product.",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              Navigator.pop(context, v ?? _qtyOf(id));
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (newQty == null) return;

    if (newQty == 0) {
      _unselect(id);
      return;
    }
    _setQty(id, newQty);
  }

  // ---------- quick add ----------
  Future<void> _quickAddProduct() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductFormScreen(vendorId: widget.vendorId),
      ),
    );

    if (created != null && created is Map<String, dynamic>) {
      if (!mounted) return;
      final id = _asInt(created['id']);
      setState(() {
        _products.insert(0, created);
        if (widget.multi && id != null) {
          _selectedIds.add(id);
          _selectedMapById[id] = created;
          _qtyById[id] = _qtyById[id] ?? 1.0;
        }
      });
      // Insert into this picker's own scope (vendor-specific or "all"),
      // and also into the unfiltered "all products" bucket if this picker
      // was vendor-scoped, since an all-products picker elsewhere should
      // still see the new product.
      ProductPickCache.cache.insertInto(
        _cacheKey,
        created,
        matchesExisting: (p) => p['id']?.toString() == created['id']?.toString(),
      );
      if (widget.vendorId != null) {
        ProductPickCache.cache.insertInto(
          ProductPickCache.keyFor(),
          created,
          matchesExisting: (p) => p['id']?.toString() == created['id']?.toString(),
        );
      }

      if (!widget.multi) {
        Future.microtask(() => Navigator.pop(context, created));
      }
    }
  }

  // ---------- return picked ----------
  List<Map<String, dynamic>> _pickedWithQty() {
    return _selectedIds.map((id) {
      return {
        "product": _selectedMapById[id] ?? {"id": id},
        "qty": _qtyOf(id),
      };
    }).toList();
  }

  int _gridCrossAxisCount(double width) {
    if (width >= 1400) return 7;
    if (width >= 1200) return 6;
    if (width >= 1000) return 5;
    if (width >= 800) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedIds.length;

    void confirmSelection() {
      if (selectedCount > 0) Navigator.pop(context, _pickedWithQty());
    }

    void closeSheet() => Navigator.pop(context);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.inventory_2_rounded, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.multi ? 'Select Products' : 'Select Product',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.multi
                                ? 'Tap products · Enter to confirm · Esc to close'
                                : 'Search and choose one product · Esc to close',
                            style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    if (widget.multi)
                      FilledButton.icon(
                        onPressed: selectedCount == 0 ? null : confirmSelection,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text('Done ($selectedCount)'),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Close  (Esc)',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: closeSheet,
                    ),
                  ],
                ),
              ),
            ),
Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: EnterprisePanel(
                padding: const EdgeInsets.all(14),
                elevated: false,
                child: Column(
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _fetchProducts(page: 1, replace: true),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        hintText: 'Search by name, SKU or barcode…',
                      ),
                    ),
                    if (_silentRefreshing)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ThinAction(
                            color: AppTheme.surfaceSoft,
                            borderColor: AppTheme.border,
                            icon: const Icon(Icons.block_rounded, color: AppTheme.textMuted),
                            label: 'No Product',
                            onTap: () => Navigator.pop(context, null),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ThinAction(
                            color: AppTheme.primarySoft,
                            borderColor: AppTheme.primary.withOpacity(.18),
                            icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary),
                            label: 'Quick Add Product',
                            onTap: _quickAddProduct,
                          ),
                        ),
                      ],
                    ),
                    if (widget.multi && selectedCount > 0) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedIds.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final id = _selectedIds.elementAt(i);
                            final p = _selectedMapById[id];
                            final label = p != null ? _name(p['name']) : 'ID: $id';
                            final qty = _qtyOf(id);

                            return _SelectedProductPill(
                              label: label,
                              qty: qty,
                              onTap: () {
                                final prod = _selectedMapById[id];
                                if (prod != null) _promptSetQty(prod);
                              },
                              onRemove: () => _unselect(id),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading && _products.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _products.isEmpty
                      ? _EmptyProducts(onQuickAdd: _quickAddProduct)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final cols = _gridCrossAxisCount(constraints.maxWidth);
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 1.02,
                              ),
                              itemCount: _products.length,
                              itemBuilder: (_, index) {
                                final p = _products[index];
                                final id = _asInt(p['id']) ?? -1;
                                final selected = _selectedIds.contains(id);
                                final qty = _qtyOf(id);

                                return _ProductGridCard(
                                  title: _name(p['name']),
                                  price: _money(p['price']),
                                  imageUrl: _imageUrl(p),
                                  selected: selected,
                                  qty: qty,
                                  onTap: () {
                                    if (!widget.multi) {
                                      Navigator.pop(context, p);
                                      return;
                                    }
                                    if (!selected) {
                                      _selectDefault(p);
                                    } else {
                                      _promptSetQty(p);
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: !_loading && _page > 1 ? () => _fetchProducts(page: _page - 1, replace: true) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Prev'),
                  ),
                  const Spacer(),
                  Text('Page $_page of $_lastPage', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMuted)),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: !_loading && _page < _lastPage ? () => _fetchProducts(page: _page + 1, replace: true) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ---------------- UI widgets ----------------


class _SelectedProductPill extends StatelessWidget {
  final String label;
  final double qty;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SelectedProductPill({
    required this.label,
    required this.qty,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final qtyLabel = qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2);
    final isNegative = qty < 0;
    final qtyColor = isNegative ? AppTheme.warning : AppTheme.primary;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 210),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: qtyColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: qtyColor.withOpacity(.22)),
                ),
                child: Text(
                  '× $qtyLabel',
                  style: TextStyle(
                    color: qtyColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  final VoidCallback onQuickAdd;

  const _EmptyProducts({required this.onQuickAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EnterprisePanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 58,
              width: 58,
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary),
            ),
            const SizedBox(height: 12),
            const Text('No products found', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 5),
            const Text('Try another keyword or quickly create a new product.', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onQuickAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Quick Add Product'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductGridCard extends StatelessWidget {
  final String title;
  final String price;
  final String? imageUrl;
  final bool selected;
  final double qty;
  final VoidCallback onTap;

  const _ProductGridCard({
    required this.title,
    required this.price,
    required this.imageUrl,
    required this.selected,
    required this.qty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Material(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? cs.primary : t.dividerColor.withOpacity(.9),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Container(
                      width: double.infinity,
                      color: cs.surfaceContainerHighest.withOpacity(.35),
                      child: imageUrl == null
                          ? Icon(Icons.fastfood,
                              size: 34, color: cs.onSurface.withOpacity(.35))
                          : Image.network(
                              imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.image_not_supported_outlined,
                                size: 28,
                                color: cs.onSurface.withOpacity(.35),
                              ),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "\$$price",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? cs.primary : cs.surface.withOpacity(.92),
                  borderRadius: BorderRadius.circular(999),
                  border: selected
                      ? null
                      : Border.all(color: t.dividerColor.withOpacity(.7)),
                ),
                child: Text(
                  selected ? "× ${qty.toStringAsFixed(0)}" : "+",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: selected ? cs.onPrimary : cs.onSurface,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinAction extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  const _ThinAction({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
