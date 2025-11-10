import 'dart:async' show Timer;
import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;
import 'package:flutter/services.dart';

/// ======= Autocomplete product model =======
class ProductRef {
  final int id;
  final String name;
  final double tp; // trade/default price
  const ProductRef({required this.id, required this.name, required this.tp});
}

/// ======= Fast POS Items Table =======
class ItemsTable extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onAddItem;
  final Future<List<ProductRef>> Function(String query) onQueryProducts;
  final void Function(List<Map<String, dynamic>> nextItems) onItemsChanged;

  const ItemsTable({
    super.key,
    required this.items,
    required this.onQueryProducts,
    required this.onItemsChanged,
    required this.onAddItem,
  });

  @override
  State<ItemsTable> createState() => _ItemsTableState();
}

class _ItemsTableState extends State<ItemsTable> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  final _rowCtrls = <int, _RowControllers>{};
  final _focusOrder = <_CellKey>[];

  // per-row commit debounce (keeps parent totals live but efficient)
  final Map<int, Timer?> _rowDebounce = {};

  // NEW: anchor for the product cell
  final LayerLink _productSearchLink = LayerLink();
  final GlobalKey _productSearchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ensureRows();
  }

  @override
  void didUpdateWidget(covariant ItemsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureRows();
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    for (final t in _rowDebounce.values) {
      t?.cancel();
    }
    for (final r in _rowCtrls.values) {
      r.dispose();
    }
    super.dispose();
  }

  void _ensureRows() {
    for (int i = 0; i < widget.items.length; i++) {
      _rowCtrls.putIfAbsent(i, () => _RowControllers());
      _syncControllersFromItem(i);
    }
    _rowCtrls.keys.where((k) => k >= widget.items.length).toList().forEach((k) {
      _rowCtrls[k]?.dispose();
      _rowCtrls.remove(k);
    });
    _rebuildFocusOrder();
  }

  void _rebuildFocusOrder() {
    _focusOrder
      ..clear()
      ..addAll(
        List.generate(widget.items.length, (i) {
          return [
            _CellKey(i, _CellField.price),
            _CellKey(i, _CellField.discount),
            _CellKey(i, _CellField.qty),
          ];
        }).expand((e) => e),
      );
  }

  void _syncControllersFromItem(int i) {
    final item = widget.items[i];
    final ctrls = _rowCtrls[i]!;
    String _fmt(num n) => n.toStringAsFixed(2);

    ctrls.name.text = (item['name'] ?? '').toString();
    ctrls.price.text = _fmt(_num(item['price']));
    ctrls.discount.text = _fmt(_num(item['discount_pct'] ?? 0));
    ctrls.qty.text = _num(item['quantity']).toStringAsFixed(0);
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  static double _calcLineTotal({
    required double price,
    required double qty,
    required double discountPct,
  }) {
    final d = (discountPct / 100.0).clamp(0.0, 100.0);
    final total = qty * price * (1.0 - d);
    return max(0.0, total);
  }

  void _scheduleCommitRow(int i) {
    _rowDebounce[i]?.cancel();
    _rowDebounce[i] = Timer(const Duration(milliseconds: 1000), () {
      _commitRow(i);
    });
  }

  void _commitRow(int i) {
    if (i < 0 || i >= widget.items.length) return;
    final ctrls = _rowCtrls[i]!;
    final item = Map<String, dynamic>.from(widget.items[i]);

    final price = _num(ctrls.price.text);
    final qty = max(0.0, double.tryParse(ctrls.qty.text) ?? 0.0);
    final disc = _num(ctrls.discount.text);

    item['price'] = price;
    item['quantity'] = qty;
    item['discount_pct'] = disc;
    item['total'] = _calcLineTotal(price: price, qty: qty, discountPct: disc);

    final next = [...widget.items];
    next[i] = item;
    widget.onItemsChanged(next);
    setState(() {}); // update displayed totals immediately
  }

  void _removeRow(int i) {
    if (i < 0 || i >= widget.items.length) return;
    final next = [...widget.items]..removeAt(i);
    widget.onItemsChanged(next);

    _rowCtrls.remove(i)?.dispose();
    final fixed = <int, _RowControllers>{};
    int idx = 0;
    for (int old = 0; old <= widget.items.length; old++) {
      if (_rowCtrls.containsKey(old)) {
        fixed[idx++] = _rowCtrls[old]!;
      }
    }
    _rowCtrls
      ..clear()
      ..addAll(fixed);
    _rebuildFocusOrder();
    setState(() {});
  }

  Future<void> _addProduct(ProductRef p) async {
    final next = [...widget.items];
    next.add({
      'product_id': p.id,
      'name': p.name,
      'price': p.tp,
      'discount_pct': 0.0,
      'quantity': 1.0,
      'total': _calcLineTotal(price: p.tp, qty: 1.0, discountPct: 0.0),
    });
    widget.onItemsChanged(next);
    _addController.clear();

    _ensureRows();
    await Future.delayed(const Duration(milliseconds: 10));
    final newIdx = next.length - 1;
    _rowCtrls[newIdx]?.priceFocus.requestFocus();
    _rowCtrls[newIdx]?.price.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _rowCtrls[newIdx]!.price.text.length,
    );
    setState(() {});
  }

  void _focusNextFrom(int row, _CellField field) {
    final idx = _focusOrder.indexOf(_CellKey(row, field));
    final nextIdx = (idx + 1).clamp(0, _focusOrder.length - 1);
    final next = _focusOrder[nextIdx];

    final ctrls = _rowCtrls[next.row];
    if (ctrls == null) return;
    switch (next.field) {
      case _CellField.price:
        ctrls.priceFocus.requestFocus();
        ctrls.price.selection = TextSelection(
          baseOffset: 0,
          extentOffset: ctrls.price.text.length,
        );
        break;
      case _CellField.discount:
        ctrls.discountFocus.requestFocus();
        ctrls.discount.selection = TextSelection(
          baseOffset: 0,
          extentOffset: ctrls.discount.text.length,
        );
        break;
      case _CellField.qty:
        ctrls.qtyFocus.requestFocus();
        ctrls.qty.selection = TextSelection(
          baseOffset: 0,
          extentOffset: ctrls.qty.text.length,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final currency = (num v) => "\$${v.toStringAsFixed(2)}";

    final totalSum = widget.items.fold<double>(
      0,
      (s, it) =>
          s +
          _calcLineTotal(
            price: _num(it['price']),
            qty: _num(it['quantity']),
            discountPct: _num(it['discount_pct'] ?? 0),
          ),
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Row(
            //   children: [
            //     const Expanded(
            //       child: Text(
            //         "Items",
            //         style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            //       ),
            //     ),
            //     SizedBox(
            //       width: 360,
            //       child: _AddProductBox(
            //         controller: _addController,
            //         focusNode: _addFocus,
            //         onQuery: widget.onQueryProducts,
            //         onSelected: _addProduct,
            //       ),
            //     ),
            //   ],
            // ),
            // const SizedBox(height: 8),
            // _TableHeader(),
            // const Divider(height: 8),
            // Title only (no search here)
            // const Align(
            //   alignment: Alignment.centerLeft,
            //   child: Text(
            //     "Items",
            //     style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            //   ),
            // ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Items",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                // If you want the vendor filter back, uncomment:
                // OutlinedButton.icon(
                //   onPressed: onPickVendor,
                //   icon: const Icon(Icons.storefront_outlined),
                //   label: Text(
                //     selectedVendor == null
                //         ? "Filter Vendor"
                //         : "Vendor: ${selectedVendor?['first_name'] ?? ''}",
                //     overflow: TextOverflow.ellipsis,
                //   ),
                // ),
                // const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: widget.onAddItem,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Item"),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Table header
            _TableHeader(),

            // Inline search row aligned with table columns
            const SizedBox(height: 6),

            if (widget.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Type a product name above and press Enter",
                    style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
                  ),
                ),
              )
            else
              ...List.generate(widget.items.length, (i) {
                final item = widget.items[i];
                final ctrls = _rowCtrls[i]!;
                final lineTotal = _calcLineTotal(
                  price: _num(ctrls.price.text),
                  qty: _num(ctrls.qty.text),
                  discountPct: _num(ctrls.discount.text),
                );

                return Column(
                  children: [
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          // Product
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                (item['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          // Price
                          Expanded(
                            flex: 2,
                            child: _CellNumberField(
                              controller: ctrls.price,
                              focusNode: ctrls.priceFocus,
                              onSubmitted: (_) {
                                _commitRow(i);
                                _focusNextFrom(i, _CellField.price);
                              },
                              onChanged: (_) {
                                setState(() {});
                                _scheduleCommitRow(i);
                              },
                            ),
                          ),
                          // Discount %
                          Expanded(
                            flex: 2,
                            child: _CellNumberField(
                              controller: ctrls.discount,
                              focusNode: ctrls.discountFocus,
                              suffix: "%",
                              onSubmitted: (_) {
                                _commitRow(i);
                                _focusNextFrom(i, _CellField.discount);
                              },
                              onChanged: (_) {
                                setState(() {});
                                _scheduleCommitRow(i);
                              },
                            ),
                          ),
                          // Qty
                          Expanded(
                            flex: 2,
                            child: _CellNumberField(
                              controller: ctrls.qty,
                              focusNode: ctrls.qtyFocus,
                              isInteger: true,
                              onSubmitted: (_) {
                                _commitRow(i);
                                _focusNextFrom(i, _CellField.qty);
                              },
                              onChanged: (_) {
                                setState(() {});
                                _scheduleCommitRow(i);
                              },
                            ),
                          ),
                          // Total
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                currency(lineTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                          // Remove
                          SizedBox(
                            width: 44,
                            child: IconButton(
                              tooltip: "Remove",
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _removeRow(i),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 8),
                  ],
                );
              }),
            _InlineSearchRow(
              productField: _AddProductBox(
                controller: _addController,
                focusNode: _addFocus,
                onQuery: widget.onQueryProducts,
                onSelected: _addProduct,
                anchorKey: _productSearchKey,
                link: _productSearchLink,
              ),
              anchorKey: _productSearchKey,
              link: _productSearchLink,
            ),
            const Divider(height: 8),
            if (widget.items.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "Total: ${currency(totalSum)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      fontFeatures: [FontFeature.tabularFigures()],
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

class _InlineSearchRow extends StatelessWidget {
  final Widget productField;
  final GlobalKey anchorKey;
  final LayerLink link;

  const _InlineSearchRow({
    required this.productField,
    required this.anchorKey,
    required this.link,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // Product column (flex: 5) – the anchor wraps the whole cell box
          Expanded(
            flex: 5,
            child: CompositedTransformTarget(
              link: link,
              child: Container(
                key: anchorKey, // we still measure this; now it has a max width
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceVariant.withOpacity(.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.dividerColor.withOpacity(.6)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                alignment: Alignment.centerLeft,

                // ⬇️ NEW: keep the field visually compact (e.g., 420px)
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: productField,
                  ),
                ),
              ),
            ),
          ),
          const Expanded(flex: 2, child: SizedBox()), // T.P
          const Expanded(flex: 2, child: SizedBox()), // Discount
          const Expanded(flex: 2, child: SizedBox()), // Qty
          const Expanded(flex: 2, child: SizedBox()), // Total
          const SizedBox(width: 44), // Remove
        ],
      ),
    );
  }
}

/// ======= Header =======
class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).hintColor,
    );
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const Expanded(flex: 5, child: Text("Product")),
          Expanded(
            flex: 2,
            child: Text("T.P", style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text(
              "Discount (%)",
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text("Qty", style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text("Total", style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// ======= Add box with robust async autocomplete =======
class _AddProductBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<List<ProductRef>> Function(String) onQuery;
  final void Function(ProductRef) onSelected;

  // NEW: injected anchor
  final GlobalKey anchorKey;
  final LayerLink link;

  const _AddProductBox({
    required this.controller,
    required this.focusNode,
    required this.onQuery,
    required this.onSelected,
    required this.anchorKey,
    required this.link,
  });

  @override
  State<_AddProductBox> createState() => _AddProductBoxState();
}

class _AddProductBoxState extends State<_AddProductBox> {
  OverlayEntry? _entry;
  List<ProductRef> _options = const [];
  bool _loading = false;
  int _highlightIndex = -1;

  // debounce/sequencing to avoid stale results
  int _seq = 0;
  Future<void>? _pending;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _removeOverlay();
    } else if (widget.controller.text.trim().isNotEmpty) {
      _showOrUpdateOverlay();
    }
  }

  void _onTextChanged() {
    final q = widget.controller.text.trim();
    if (q.isEmpty) {
      _options = const [];
      _highlightIndex = -1;
      _removeOverlay();
      setState(() {});
      return;
    }
    _debouncedFetch(q);
  }

  void _debouncedFetch(String q) {
    final mySeq = ++_seq;
    _pending = Future.delayed(const Duration(milliseconds: 180)).then((
      _,
    ) async {
      if (!mounted || mySeq != _seq) return;
      setState(() => _loading = true);
      try {
        final res = await widget.onQuery(q);
        if (!mounted || mySeq != _seq) return;
        _options = res;
        _highlightIndex = _options.isEmpty ? -1 : 0; // default to first
        _showOrUpdateOverlay();
      } finally {
        if (mounted && mySeq == _seq) setState(() => _loading = false);
      }
    });
  }

  void _showOrUpdateOverlay() {
    if (!widget.focusNode.hasFocus) return;
    if (_entry == null) {
      _entry = OverlayEntry(builder: (context) => _buildOverlay());
      Overlay.of(context, rootOverlay: true).insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _moveHighlight(int delta) {
    if (_options.isEmpty) return;
    setState(() {
      _highlightIndex = (_highlightIndex + delta).clamp(0, _options.length - 1);
    });
    _entry?.markNeedsBuild();
  }

  void _pickHighlighted() {
    if (_options.isEmpty) return;
    final idx = _highlightIndex < 0 ? 0 : _highlightIndex;
    _select(_options[idx]);
  }

  void _select(ProductRef p) {
    widget.onSelected(p);
    widget.controller.clear();
    _options = const [];
    _highlightIndex = -1;
    _showOrUpdateOverlay(); // hides (empty list)
    Future.microtask(() => widget.focusNode.requestFocus());
  }

  Widget _buildOverlay() {
    if (!mounted) return const SizedBox.shrink();

    final anchorBox =
        widget.anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null || !anchorBox.attached)
      return const SizedBox.shrink();

    const double kSearchMaxWidth = 420;
    final anchorWidth = anchorBox.size.width;
    final popupWidth = anchorWidth.clamp(0, kSearchMaxWidth);

    final theme = Theme.of(context);

    return CompositedTransformFollower(
      link: widget.link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft, // align edges
      followerAnchor: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: SizedBox(
          width: popupWidth.toDouble(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: _options.isEmpty
                ? (_loading
                      ? Container(
                          height: 44,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: const [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text("Searching…"),
                            ],
                          ),
                        )
                      : const SizedBox.shrink())
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _options.length,
                    itemBuilder: (ctx, i) {
                      final p = _options[i];
                      final isHi = i == _highlightIndex;
                      return InkWell(
                        onTap: () => _select(p),
                        child: Container(
                          color: isHi ? theme.focusColor.withOpacity(.2) : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                "\$${p.tp.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKey: (node, RawKeyEvent event) {
        if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
        if (_entry == null) return KeyEventResult.ignored;

        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          _moveHighlight(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _moveHighlight(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          _pickHighlighted();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.tab) {
          _pickHighlighted();
          return KeyEventResult.handled; // keep focus here
        }
        if (key == LogicalKeyboardKey.escape) {
          _removeOverlay();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: double.infinity,
        child: TextField(
          controller: widget.controller,
          decoration: InputDecoration(
            hintText: "Add item… type name / scan barcode",
            prefixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.only(left: 12, right: 6),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search, size: 18),
            isDense: true,
            border: InputBorder.none, // merges into the cell styling
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 6,
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _pickHighlighted(),
        ),
      ),
    );
  }
}

/// ======= Numeric cell editor =======
class _CellNumberField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String suffix;
  final bool isInteger;
  final void Function(String)? onSubmitted;
  final void Function(String)? onChanged;

  const _CellNumberField({
    required this.controller,
    required this.focusNode,
    this.suffix = "",
    this.isInteger = false,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      onSubmitted: onSubmitted,
      onChanged: (v) {
        if (isInteger) {
          final onlyInt = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
          if (onlyInt != null && onlyInt.toString() != v) {
            controller.text = onlyInt.toString();
            controller.selection = TextSelection.fromPosition(
              TextPosition(offset: controller.text.length),
            );
          }
        }
        onChanged?.call(controller.text);
      },
      onTap: () {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      },
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        suffixText: suffix.isEmpty ? null : suffix,
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// ======= Row controllers =======
class _RowControllers {
  final name = TextEditingController();
  final price = TextEditingController();
  final discount = TextEditingController();
  final qty = TextEditingController();

  final priceFocus = FocusNode();
  final discountFocus = FocusNode();
  final qtyFocus = FocusNode();

  void dispose() {
    name.dispose();
    price.dispose();
    discount.dispose();
    qty.dispose();
    priceFocus.dispose();
    discountFocus.dispose();
    qtyFocus.dispose();
  }
}

enum _CellField { price, discount, qty }

class _CellKey {
  final int row;
  final _CellField field;
  const _CellKey(this.row, this.field);
  @override
  bool operator ==(Object other) =>
      other is _CellKey && other.row == row && other.field == field;
  @override
  int get hashCode => Object.hash(row, field);
}

/// ======= Mock backend for demo only – remove in prod =======
Future<Map<String, dynamic>> _fakeGetProducts(String q) async {
  await Future.delayed(const Duration(milliseconds: 120));
  final all =
      [
            {'id': 1, 'name': 'no vendor pro', 'price': '800.00'},
            {'id': 2, 'name': 'notebook deluxe', 'price': '1200.00'},
            {'id': 3, 'name': 'novel charger', 'price': '450.00'},
            {'id': 4, 'name': 'adapter C', 'price': '350.00'},
          ]
          .where(
            (m) =>
                (m['name'] as String).toLowerCase().contains(q.toLowerCase()),
          )
          .toList();

  return {
    'success': true,
    'data': [
      {
        'products': all,
        'total': all.length,
        'per_page': 15,
        'current_page': 1,
        'last_page': 1,
      },
    ],
  };
}
