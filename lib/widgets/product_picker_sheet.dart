import 'dart:async';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/product_form_screen.dart';
import 'package:flutter/material.dart';

class ProductPickerSheet extends StatefulWidget {
  final String token;
  final int? vendorId;
  final bool multi; // NEW

  const ProductPickerSheet({
    super.key,
    required this.token,
    this.vendorId,
    this.multi = false,
  });

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  final List<Map<String, dynamic>> _products = [];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = false;
  String _search = "";
  Timer? _debounce;

  // 🔍 search controller & focus
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  late ProductService _productService;

  @override
  void initState() {
    super.initState();
    _productService = ProductService(token: widget.token);

    // Auto-focus the search once the sheet is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });

    _fetchProducts(page: 1, replace: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

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
      setState(() => _products.insert(0, created));
      // Immediately return the new product
      Future.microtask(() => Navigator.pop(context, created));
    }
  }

  Future<void> _fetchProducts({required int page, bool replace = true}) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final data = await _productService.getProducts(
        page: page,
        search: _search,
        vendorId: widget.vendorId,
      );

      // ... your flexible parsing (unchanged) ...
      List<Map<String, dynamic>> newProducts = [];
      int currentPage = 1;
      int lastPage = 1;

      dynamic root = data['data'] ?? data;
      if (root is List && root.isNotEmpty) root = root.first;

      dynamic productsNode = (root is Map)
          ? (root['products'] ?? root['data'] ?? root)
          : root;

      if (productsNode is Map) {
        final listNode = productsNode['data'];
        if (listNode is List) {
          newProducts = listNode.cast<Map<String, dynamic>>();
        }
        currentPage =
            (productsNode['current_page'] ?? root['current_page'] ?? page)
                as int;
        lastPage = (productsNode['last_page'] ?? root['last_page'] ?? 1) as int;
      } else if (productsNode is List) {
        newProducts = productsNode.cast<Map<String, dynamic>>();
        currentPage = page;
        lastPage = (root is Map ? (root['last_page'] ?? 1) : 1) as int;
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
        _page = page; // ← trust the requested page
        _lastPage = lastPage;
      });

      // Optional: jump list to top when page changes
      // if (replace && _listCtrl.hasClients) _listCtrl.jumpTo(0);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      setState(() => _search = val.trim());
      _fetchProducts(page: 1, replace: true);
    });
  }

  final Set<int> _selectedIds = {}; // NEW
  // helper to toggle selection
  void _toggleSelect(Map<String, dynamic> p) {
    final id = (p['id'] as num).toInt();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // build Done bar (only in multi mode)
  Widget _buildMultiDoneBar() {
    if (!widget.multi) return const SizedBox.shrink();
    final picked = _products
        .where((p) => _selectedIds.contains((p['id'] as num).toInt()))
        .toList();
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Text(
              "${picked.length} selected",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: picked.isEmpty
                  ? null
                  : () => Navigator.pop(context, picked),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text("Done"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    const visualDense = VisualDensity(horizontal: -2, vertical: -3);
    const contentDense = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
        child: Column(
          children: [
            // Title + Close
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Select Product",
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 20,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 🔍 Search (auto-focused, compact)
            TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _fetchProducts(page: 1, replace: true),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_searchCtrl.text.isNotEmpty)
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged("");
                        },
                      )
                    : null,
                hintText: "Search product…",
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Quick choices row (no cards; subtle containers)
            Row(
              children: [
                Expanded(
                  child: _ThinAction(
                    color: Colors.grey.shade100,
                    borderColor: t.dividerColor,
                    icon: const Icon(Icons.clear, color: Colors.red),
                    label: "No Product",
                    onTap: () => Navigator.pop(context, null),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ThinAction(
                    color: Colors.green.shade50,
                    borderColor: Colors.green.shade200,
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.green,
                    ),
                    label: "Quick Add",
                    onTap: _quickAddProduct,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 📋 Products (dense, separated)
            Expanded(
              child: _loading && _products.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _products.isEmpty
                  ? const Center(child: Text("No products found"))
                  : ListView.separated(
                      itemCount: _products.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.6,
                        color: t.dividerColor.withOpacity(0.6),
                      ),
                      itemBuilder: (_, index) {
                        final p = _products[index];
                        final name = (p['name'] ?? 'Unnamed').toString();
                        final sku = (p['sku'] ?? '-').toString();
                        final category =
                            (p['category']?['name'] ?? 'Uncategorized')
                                .toString();
                        final priceStr = (p['price']?.toString() ?? '0');
                        final discountStr = (p['discount']?.toString() ?? '0');
                        final id = (p['id'] as num).toInt();
                        final selected = _selectedIds.contains(id);

                        return ListTile(
                          dense: true,
                          visualDensity: visualDense,
                          contentPadding: contentDense,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                "\$$priceStr",
                                style: t.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "SKU: $sku • $category",
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (discountStr != "0")
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    "-\$$discountStr",
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: widget.multi
                              ? Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggleSelect(p),
                                )
                              : const Icon(Icons.chevron_right, size: 18),
                          onTap: () {
                            if (widget.multi) {
                              _toggleSelect(p);
                            } else {
                              Navigator.pop(context, p); // single
                            }
                          },
                        );
                      },
                    ),
            ),

            // ⏩ Pagination (compact)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: !_loading && _page > 1
                      ? () => _fetchProducts(page: _page - 1, replace: true)
                      : null,
                  child: const Text("Prev"),
                ),
                const SizedBox(width: 8),
                Text(
                  "$_page / $_lastPage",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: !_loading && _page < _lastPage
                      ? () => _fetchProducts(page: _page + 1, replace: true)
                      : null,
                  child: const Text("Next"),
                ),
              ],
            ),

            // multi-done bar
            _buildMultiDoneBar(),
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
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
