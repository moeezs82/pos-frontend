import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'dart:ui' show FontFeature;
import 'package:flutter/services.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_panel.dart';

/// ======= Autocomplete product model =======
class ProductRef {
  final int id;
  final String name;
  final double tp; // trade/default price
  final String? sku;
  final String? barcode;
  final double? stock;
  final Map<String, dynamic>? raw; // original API map for _applyPickedProduct

  const ProductRef({
    required this.id,
    required this.name,
    required this.tp,
    this.sku,
    this.barcode,
    this.stock,
    this.raw,
  });

  /// The quantity contract for this product, read from [raw].
  ///
  /// [raw] is whatever the search returned — a live `/products` row (nested
  /// `unit` object) or a local-cache row (flat `unit_*` columns).
  /// [QuantityRule.fromProduct] handles both, and a product with no unit
  /// information yields the permissive rule.
  QuantityRule get quantityRule => QuantityRule.fromProduct(raw);
}

/// ======= Fast POS Items Table =======
class ItemsTable extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onAddItem;
  final Future<List<ProductRef>> Function(String query) onQueryProducts;
  final void Function(List<Map<String, dynamic>> nextItems) onItemsChanged;

  /// When [compact] is true the table renders as a plain borderless table
  /// (no EnterprisePanel card, no section header, tighter row padding)
  /// suitable for embedding inside the reference-style left panel layout.
  final bool compact;

  const ItemsTable({
    super.key,
    required this.items,
    required this.onQueryProducts,
    required this.onItemsChanged,
    required this.onAddItem,
    this.compact = false,
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

  /// Per-row quantity rule violation, keyed by row index.
  ///
  /// The input formatter already refuses an illegal keystroke or paste, so
  /// this is for the cases it cannot cover: a line whose product was added
  /// before the rule was known, and a line whose quantity was set
  /// programmatically (picker sheet, barcode increment).
  final Map<int, String> _qtyErrors = {};

  /// Rate-limits the "whole numbers only" toast. Holding the "." key would
  /// otherwise fire one per keystroke.
  DateTime? _lastRejectionToast;

  /// The quantity contract for row [i], re-read from the line on every build
  /// so replacing a line's product immediately replaces its rule.
  QuantityRule _ruleFor(int i) {
    if (i < 0 || i >= widget.items.length) return QuantityRule.permissive;
    return QuantityRule.fromProduct(widget.items[i]);
  }

  /// Called when the formatter refuses an edit. The refusal is silent by
  /// itself — nothing changes on screen — so say why.
  void _onQtyRejected(int i) {
    final message = _ruleFor(i).message;
    setState(() => _qtyErrors[i] = message);
    final now = DateTime.now();
    final last = _lastRejectionToast;
    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _lastRejectionToast = now;
      AppFeedback.warning(context, message);
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureRows();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addFocus.requestFocus();
    });
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
    ctrls.qty.text = _formatQty(_num(item['quantity']));
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  static String _formatQty(double value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static double _calcLineTotal({
    required double price,
    required double qty,
    required double discountPct,
    String discountType = 'percentage',
  }) {
    final double total;
    if (discountType == 'fixed') {
      total = qty * (price - discountPct);
    } else {
      final d = (discountPct / 100.0).clamp(0.0, 100.0);
      total = qty * price * (1.0 - d);
    }
    return (total.isFinite && total >= 0) ? total : 0.0;
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

    final price       = _num(ctrls.price.text);
    final qty         = double.tryParse(ctrls.qty.text.trim()) ?? 0.0;
    final disc        = _num(ctrls.discount.text);
    final discountType = (item['discount_type'] ?? 'percentage').toString();

    item['price'] = price;
    item['quantity'] = qty;
    item['discount_pct'] = disc;
    item['total'] = _calcLineTotal(price: price, qty: qty, discountPct: disc, discountType: discountType);

    // The quantity is committed as typed even when it breaks the rule — never
    // silently rounded. The violation is recorded so the field shows it and
    // the screen's pre-flight check can block the save.
    final rule = QuantityRule.fromProduct(item);
    if (rule.allows(qty)) {
      _qtyErrors.remove(i);
    } else {
      _qtyErrors[i] = rule.message;
    }

    final next = [...widget.items];
    next[i] = item;
    widget.onItemsChanged(next);
    setState(() {}); // update displayed totals immediately
  }

  /// Toggles the discount type for row [i] between 'percentage' and 'fixed',
  /// then recomputes the line total immediately with the new type.
  void _toggleDiscountType(int i) {
    if (i < 0 || i >= widget.items.length) return;
    final next = [...widget.items];
    final item = Map<String, dynamic>.from(next[i]);
    final current = (item['discount_type'] ?? 'percentage').toString();
    item['discount_type'] = current == 'percentage' ? 'fixed' : 'percentage';
    final ctrls = _rowCtrls[i]!;
    final price = _num(ctrls.price.text);
    final qty   = double.tryParse(ctrls.qty.text.trim()) ?? 0.0;
    final disc  = _num(ctrls.discount.text);
    item['total'] = _calcLineTotal(
      price: price,
      qty: qty,
      discountPct: disc,
      discountType: item['discount_type'].toString(),
    );
    next[i] = item;
    widget.onItemsChanged(next);
    setState(() {});
  }

  void _removeRow(int i) {
    if (i < 0 || i >= widget.items.length) return;
    final next = [...widget.items]..removeAt(i);
    widget.onItemsChanged(next);

    // Errors are keyed by row index, and every index after i shifts down.
    // Rather than re-map them, drop the lot — _commitRow re-derives an error
    // for any row that still has one, and the screen's pre-flight check is
    // the real guard.
    _qtyErrors.clear();

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
    final discPct  = double.tryParse(p.raw?['discount']?.toString() ?? '') ?? 0.0;
    final discType = (p.raw?['discount_type'] ?? 'percentage').toString();
    final next = [...widget.items];
    next.add({
      'product_id': p.id,
      'name': p.name,
      'price': p.tp,
      'discount_pct': discPct,
      'discount_type': discType,
      'quantity': 1.0,
      'total': _calcLineTotal(price: p.tp, qty: 1.0, discountPct: discPct, discountType: discType),
      // Carry the quantity contract on the line: the search result that knew
      // it is discarded as soon as this returns.
      ...p.quantityRule.toRowFields(),
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
    if (widget.compact) return _buildCompact(context);
    return _buildFull(context);
  }

  // ── Full (non-compact) build ────────────────────────────────────────────
  Widget _buildFull(BuildContext context) {
    final t = Theme.of(context);
    final currency = (num v) => AppCurrency.format(v);

    final totalSum = widget.items.fold<double>(
      0,
      (s, it) =>
          s +
          _calcLineTotal(
            price: _num(it['price']),
            qty: _num(it['quantity']),
            discountPct: _num(it['discount_pct'] ?? 0),
            discountType: (it['discount_type'] ?? 'percentage').toString(),
          ),
    );

    return EnterprisePanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: EnterpriseSectionHeader(
              title: 'Invoice items',
              subtitle: 'Search inline, scan barcode, or open full product selector.',
              icon: Icons.inventory_2_outlined,
              color: AppTheme.primary,
              trailing: FilledButton.icon(
                onPressed: widget.onAddItem,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Item'),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                _TableHeader(),
                const SizedBox(height: 7),
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
              ],
            ),
          ),
          if (widget.items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft.withOpacity(.55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.primary.withOpacity(.10)),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Icon(Icons.touch_app_rounded, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Start by selecting products',
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The product selector opens automatically on this screen. You can also type product name above or scan barcode.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodySmall?.copyWith(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                children: List.generate(widget.items.length, (i) {
                  final item = widget.items[i];
                  final ctrls = _rowCtrls[i]!;
                  final rowDiscType = (item['discount_type'] ?? 'percentage').toString();
                  final lineTotal = _calcLineTotal(
                    price: _num(ctrls.price.text),
                    qty: _num(ctrls.qty.text),
                    discountPct: _num(ctrls.discount.text),
                    discountType: rowDiscType,
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                              children: [
                                Container(
                                  height: 34,
                                  width: 34,
                                  decoration: BoxDecoration(
                                    color: AppTheme.teal.withOpacity(.10),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.shopping_bag_outlined, size: 18, color: AppTheme.teal),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    (item['name'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _CellNumberField(
                                  controller: ctrls.discount,
                                  focusNode: ctrls.discountFocus,
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
                              const SizedBox(width: 5),
                              _DiscTypeBadge(
                                isFixed: rowDiscType == 'fixed',
                                onTap: () => _toggleDiscountType(i),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _CellNumberField(
                            controller: ctrls.qty,
                            focusNode: ctrls.qtyFocus,
                            allowNegative: true,
                            rule: _ruleFor(i),
                            errorText: _qtyErrors[i] ??
                                _ruleFor(i).validateText(ctrls.qty.text),
                            onRejected: () => _onQtyRejected(i),
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
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              currency(lineTotal),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: lineTotal < 0 ? AppTheme.warning : AppTheme.navy,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded, color: AppTheme.danger),
                            onPressed: () => _removeRow(i),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Text(
                    '${widget.items.length} item${widget.items.length == 1 ? '' : 's'} in invoice',
                    style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.success.withOpacity(.14)),
                    ),
                    child: Text(
                      'Items Total: ${currency(totalSum)}',
                      style: const TextStyle(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Compact build: returns a ListView so the parent can give it
  //    an Expanded container for independent scrolling.
  //    The table header is NOT rendered here — the parent renders it
  //    as a fixed element above this ListView.
  Widget _buildCompact(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No items yet.\nType in the search bar above or scan a barcode.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: widget.items.length,
      itemBuilder: (ctx, i) => _buildCompactRow(i),
    );
  }

  Widget _buildCompactRow(int i) {
    final item = widget.items[i];
    final ctrls = _rowCtrls[i]!;
    final compactDiscType = (item['discount_type'] ?? 'percentage').toString();
    final lineTotal = _calcLineTotal(
      price: _num(ctrls.price.text),
      qty: _num(ctrls.qty.text),
      discountPct: _num(ctrls.discount.text),
      discountType: compactDiscType,
    );

    return Container(
      height: 58,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Product name — no icon, flexible
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                (item['name'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
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
              compact: true,
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
          const SizedBox(width: 4),
          // Discount
          Expanded(
            flex: 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _CellNumberField(
                    controller: ctrls.discount,
                    focusNode: ctrls.discountFocus,
                    compact: true,
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
                const SizedBox(width: 3),
                _DiscTypeBadge(
                  isFixed: compactDiscType == 'fixed',
                  compact: true,
                  onTap: () => _toggleDiscountType(i),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Qty — plain editable field (no ± buttons)
          Expanded(
            flex: 3,
            child: _CellNumberField(
              controller: ctrls.qty,
              focusNode: ctrls.qtyFocus,
              allowNegative: true,
              compact: true,
              rule: _ruleFor(i),
              errorText:
                  _qtyErrors[i] ?? _ruleFor(i).validateText(ctrls.qty.text),
              onRejected: () => _onQtyRejected(i),
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
          const SizedBox(width: 4),
          // Line total (no-wrap)
          Expanded(
            flex: 2,
            child: Text(
              AppCurrency.format(lineTotal),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: lineTotal < 0 ? AppTheme.warning : AppTheme.navy,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // Remove button
          SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Remove',
              icon: const Icon(
                Icons.close_rounded,
                color: AppTheme.danger,
                size: 16,
              ),
              onPressed: () => _removeRow(i),
            ),
          ),
        ],
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
          const Expanded(flex: 3, child: SizedBox()), // Discount
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
            flex: 3,
            child: Text("Discount", style: style, textAlign: TextAlign.right),
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

  /// Binds this field and its suggestion overlay into ONE tap region.
  ///
  /// The overlay lives in the ROOT overlay, so Flutter treats a click on it as
  /// a tap OUTSIDE the TextField; EditableText's default onTapOutside then
  /// unfocuses on pointer-DOWN, _onFocusChanged tore the overlay down, and the
  /// tap died before pointer-up. That is why only Enter selected a product.
  final Object _tapGroup = Object();
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
      // Only keyboard traversal / programmatic unfocus reach here now.
      // Mouse dismissal is handled by TapRegion.onTapOutside, so a click on a
      // suggestion no longer destroys the overlay before it can be selected.
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

    // TextFieldTapRegion == TapRegion(groupId: EditableText). It is the ONLY
    // thing that stops EditableText's default onTapOutside from unfocusing the
    // search field on pointer-DOWN when the click lands on this panel. Without
    // it the field blurs, the overlay is torn down, and the tap is cancelled
    // before pointer-UP reaches the InkWell — which is why only Enter worked.
    // The inner TapRegion keeps our own outside-tap dismissal correct.
    return TextFieldTapRegion(
      child: TapRegion(
      groupId: _tapGroup,
      child: CompositedTransformFollower(
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
                        canRequestFocus: false,
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
                                AppCurrency.format(p.tp),
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
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) => _removeOverlay(),
      child: Focus(
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
      ),
    );
  }
}

/// ======= Numeric cell editor =======
/// Blocks any edit that would leave a fractional quantity in a field whose
/// unit does not allow one.
///
/// Rejection means "keep the old value", never "round the new one" — a
/// formatter that stripped the "." would turn a pasted 1.5 into 15, which is
/// far worse than refusing it. The refusal is invisible on its own, so
/// [onRejected] fires and the caller explains it.
class _WholeQuantityFormatter extends TextInputFormatter {
  final VoidCallback? onRejected;

  const _WholeQuantityFormatter({this.onRejected});

  /// Optional sign, digits only. An empty field and a lone "-" are allowed
  /// through so the field can be cleared and a negative can be typed.
  static final RegExp _allowed = RegExp(r'^-?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_allowed.hasMatch(newValue.text)) return newValue;
    onRejected?.call();
    return oldValue;
  }
}

class _CellNumberField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String suffix;
  final bool allowNegative;
  final bool compact;
  final void Function(String)? onSubmitted;
  final void Function(String)? onChanged;

  /// When set, the suffix label becomes a tappable chip (used for the
  /// discount type toggle — cashier taps '%' or 'fx' to switch type).
  final VoidCallback? onSuffixTap;

  /// The quantity contract for this line, when the field is a quantity.
  /// Null (the default) for price/discount, which are always decimal.
  final QuantityRule? rule;

  /// A rule violation to show. Kept separate from [rule] because a violation
  /// can outlive the text that caused it (a rejected paste changes nothing).
  final String? errorText;

  /// Fires when an edit is refused for breaking [rule].
  final VoidCallback? onRejected;

  const _CellNumberField({
    required this.controller,
    required this.focusNode,
    this.suffix = "",
    this.allowNegative = false,
    this.compact = false,
    this.onSubmitted,
    this.onChanged,
    this.onSuffixTap,
    this.rule,
    this.errorText,
    this.onRejected,
  });

  // ignore: unused_element — suffix/onSuffixTap kept for API compat but
  // the discount badge is now rendered externally via _DiscTypeBadge.

  bool get _wholeOnly => rule != null && !rule!.allowDecimal;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(compact ? 3 : 4)),
      borderSide: const BorderSide(color: AppTheme.danger, width: 1.4),
    );

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: TextAlign.right,
      // decimal: false also asks a soft keyboard not to offer a decimal key.
      // It is a hint, not a guarantee — the formatter is what enforces.
      keyboardType: TextInputType.numberWithOptions(
        decimal: !_wholeOnly,
        signed: allowNegative,
      ),
      inputFormatters: _wholeOnly
          ? [_WholeQuantityFormatter(onRejected: onRejected)]
          : null,
      textInputAction: TextInputAction.next,
      onSubmitted: onSubmitted,
      onChanged: (v) {
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
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        // Badge is rendered externally as _DiscTypeBadge; no suffix chrome here.
        suffixText: suffix.isEmpty ? null : suffix,
        // The compact row has a fixed 58px height, so an errorText label under
        // the field would overflow it. There the red border plus the tooltip
        // carry the message instead.
        errorText: (hasError && !compact) ? errorText : null,
        errorMaxLines: 2,
        errorStyle: const TextStyle(fontSize: 10, height: 1.1),
        border: compact
            ? const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
              )
            : const OutlineInputBorder(),
        enabledBorder: hasError ? errorBorder : null,
        focusedBorder: hasError ? errorBorder : null,
      ),
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: compact ? 12 : 14,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (!hasError && !_wholeOnly) return field;
    return Tooltip(
      message: hasError
          ? errorText!
          : 'Whole numbers only${rule!.unitName.isEmpty ? '' : ' — unit "${rule!.unitName}"'}.',
      child: field,
    );
  }
}

/// ======= Discount type toggle badge =======
/// Rendered next to the discount TextField (not inside it as a suffixIcon),
/// giving a clean InkWell ripple and an AnimatedContainer colour transition.
class _DiscTypeBadge extends StatelessWidget {
  final bool isFixed;
  final bool compact;
  final VoidCallback onTap;

  const _DiscTypeBadge({
    required this.isFixed,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final double w = compact ? 26 : 30;
    final double h = compact ? 30 : 36;
    final label = isFixed ? 'Fx' : '%';
    final bg    = isFixed ? AppTheme.primary.withOpacity(.13) : Colors.grey.shade100;
    final border = isFixed ? AppTheme.primary.withOpacity(.45) : Colors.grey.shade300;
    final fg    = isFixed ? AppTheme.primary : Colors.grey.shade500;

    return Tooltip(
      message: isFixed
          ? 'Fixed amount — tap to switch to %'
          : 'Percentage — tap to switch to fixed',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
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
