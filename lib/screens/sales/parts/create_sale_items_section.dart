import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/sale_profit.dart';
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
  final void Function(int index)? onProfitInsight;
  final void Function(int index)? onEditSellingUnit;
  final void Function(int index, int? packagingId)? onSellingUnitChanged;
  final Future<bool> Function(int index, double returnQuantity)? onReturnLinkRequested;

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
    this.onProfitInsight,
    this.onEditSellingUnit,
    this.onSellingUnitChanged,
    this.onReturnLinkRequested,
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
  int? _hoveredRow;
  final Set<int> _returnLinkInProgress = <int>{};

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
      _rowCtrls.putIfAbsent(i, () {
        late final _RowControllers ctrls;
        ctrls = _RowControllers(
          onEditingBlur: () => _commitControllersIfDirty(ctrls),
        );
        return ctrls;
      });
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

    final nameText = (item['name'] ?? '').toString();
    final packaged = _isPackaged(item);
    final priceText = _fmt(packaged
        ? _num(item['packaging_unit_price'])
        : _num(item['price']));
    final discountType = (item['discount_type'] ?? 'percentage').toString();
    final discountText = _fmt(packaged && discountType == 'fixed'
        ? _num(item['packaging_discount_snapshot'])
        : _num(item['discount_pct'] ?? 0));
    final qtyText = _formatQty(packaged
        ? _num(item['packaging_quantity'])
        : _num(item['quantity']));

    // Do not rewrite a numeric controller while the cashier is editing it.
    // A debounced row commit updates the parent, which rebuilds this widget;
    // assigning controller.text during that rebuild resets the selection/caret
    // and can turn a slowly typed "25" into "5". The focused field is the
    // source of truth until editing finishes.
    if (ctrls.name.text != nameText) {
      ctrls.name.text = nameText;
    }
    final forceExternalSync = !ctrls.dirty;
    _syncEditableController(
      ctrls.price,
      ctrls.priceFocus,
      priceText,
      force: forceExternalSync,
    );
    _syncEditableController(
      ctrls.discount,
      ctrls.discountFocus,
      discountText,
      force: forceExternalSync,
    );
    _syncEditableController(
      ctrls.qty,
      ctrls.qtyFocus,
      qtyText,
      force: forceExternalSync,
    );
  }

  void _syncEditableController(
    TextEditingController controller,
    FocusNode focusNode,
    String value, {
    bool force = false,
  }) {
    if ((!force && focusNode.hasFocus) || controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  static double _round2(double value) =>
      (value * 100).roundToDouble() / 100;

  static double _round3(double value) =>
      (value * 1000).roundToDouble() / 1000;

  static double _round4(double value) =>
      (value * 10000).roundToDouble() / 10000;

  static bool _isPackaged(Map<String, dynamic> item) =>
      item['packaging_id'] != null;

  static bool _hasPackagingChoices(Map<String, dynamic> item) {
    final values = item['packagings'];
    if (values is! List) return false;
    for (final raw in values) {
      if (raw is! Map) continue;
      final active = raw['is_active'];
      final isActive = active == null ||
          active == true ||
          active == 1 ||
          active.toString().toLowerCase() == 'true';
      if (isActive && _num(raw['base_quantity']) > 0) return true;
    }
    return false;
  }

  static String _sellingUnitSummary(Map<String, dynamic> item) {
    if (_isPackaged(item)) {
      final name = (item['packaging_short_name_snapshot'] ??
              item['packaging_name_snapshot'] ??
              'Package')
          .toString();
      final factor = _num(item['packaging_factor_snapshot']);
      final baseUnit = (item['unit_name'] ?? '').toString().trim();
      final factorText = _formatQty(factor);
      return baseUnit.isEmpty
          ? '$name • 1 = $factorText base units'
          : '$name • 1 = $factorText $baseUnit';
    }
    final baseUnit = (item['unit_name'] ?? '').toString().trim();
    return baseUnit.isEmpty ? 'Base unit • Change selling unit' : '$baseUnit • Change selling unit';
  }

  Widget _buildSellingUnitMenu(
    int index,
    Map<String, dynamic> item, {
    bool compact = false,
  }) {
    final currentId = int.tryParse(item['packaging_id']?.toString() ?? '') ?? 0;
    final baseUnit = (item['unit_name'] ?? '').toString().trim();
    final choices = <PopupMenuEntry<int>>[
      PopupMenuItem<int>(
        value: 0,
        child: Row(
          children: [
            Icon(
              currentId == 0 ? Icons.check_rounded : Icons.inventory_2_outlined,
              size: 16,
              color: currentId == 0 ? AppTheme.success : AppTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(baseUnit.isEmpty ? 'Base unit' : baseUnit)),
          ],
        ),
      ),
    ];
    final rawPackages = item['packagings'];
    if (rawPackages is List) {
      for (final raw in rawPackages) {
        if (raw is! Map) continue;
        final id = int.tryParse(raw['id']?.toString() ?? '');
        final factor = _num(raw['base_quantity']);
        final activeRaw = raw['is_active'];
        final active = activeRaw == null ||
            activeRaw == true ||
            activeRaw == 1 ||
            activeRaw.toString().toLowerCase() == 'true';
        if (id == null || id <= 0 || factor <= 0 || !active) continue;
        final name = (raw['name'] ?? 'Package').toString().trim();
        final short = (raw['short_name'] ?? '').toString().trim();
        final title = short.isEmpty || short.toLowerCase() == name.toLowerCase()
            ? name
            : '$name ($short)';
        final factorText = _formatQty(factor);
        choices.add(
          PopupMenuItem<int>(
            value: id,
            child: Row(
              children: [
                Icon(
                  currentId == id ? Icons.check_rounded : Icons.inventory_2_outlined,
                  size: 16,
                  color: currentId == id ? AppTheme.success : AppTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        baseUnit.isEmpty
                            ? '1 = $factorText base units'
                            : '1 = $factorText $baseUnit',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
    choices
      ..add(const PopupMenuDivider())
      ..add(
        const PopupMenuItem<int>(
          value: -1,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Text('Advanced item edit'),
            ],
          ),
        ),
      );

    return PopupMenuButton<int>(
      tooltip: 'Change selling unit',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onOpened: () => _commitRow(index),
      onSelected: (value) {
        if (value == -1) {
          widget.onEditSellingUnit?.call(index);
          return;
        }
        widget.onSellingUnitChanged?.call(index, value == 0 ? null : value);
      },
      itemBuilder: (_) => choices,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _sellingUnitSummary(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          Icon(Icons.arrow_drop_down_rounded, size: compact ? 14 : 16, color: AppTheme.primary),
        ],
      ),
    );
  }

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
    return total.isFinite ? total : 0.0;
  }

  static double _displayLineTotal(
    Map<String, dynamic> item, {
    required double price,
    required double qty,
    required double discountPct,
    required String discountType,
  }) {
    if (qty < 0 && item['original_sale_item_id'] != null) {
      return -_num(item['return_credit']).abs();
    }
    if (_isPackaged(item)) {
      // For packaged rows [price], [qty] and [discountPct] are the currently
      // displayed selling-unit values. This keeps totals live while the cashier
      // is typing instead of waiting for the debounced parent-state commit.
      final packageQty = qty;
      final packagePrice = price;
      final gross = _round2(packageQty * packagePrice);
      final lineDiscount = discountType == 'fixed'
          ? _round2(packageQty * discountPct)
          : _round2(gross * (discountPct.clamp(0.0, 100.0) / 100.0));
      return _round2(gross - lineDiscount);
    }
    return _calcLineTotal(
      price: price,
      qty: qty,
      discountPct: discountPct,
      discountType: discountType,
    );
  }

  void _scheduleCommitRow(int i) {
    final ctrls = _rowCtrls[i];
    if (ctrls == null) return;
    ctrls.dirty = true;
    _rowDebounce[i]?.cancel();
    _rowDebounce[i] = Timer(const Duration(milliseconds: 1000), () {
      _commitRow(i);
    });
  }

  void _commitControllersIfDirty(_RowControllers ctrls) {
    if (!ctrls.dirty) return;
    for (final entry in _rowCtrls.entries) {
      if (identical(entry.value, ctrls)) {
        _commitRow(entry.key);
        return;
      }
    }
  }

  void _commitRow(int i) {
    _rowDebounce[i]?.cancel();
    _rowDebounce[i] = null;
    if (i < 0 || i >= widget.items.length) return;
    final ctrls = _rowCtrls[i]!;
    final item = Map<String, dynamic>.from(widget.items[i]);

    // A packaged row displays package quantity in the Qty cell while stock/COGS
    // still use canonical base quantity. Commit the two atomically so editing
    // `2 Box -> 3 Box` can never leave packaging_quantity and quantity out of sync.
    if (_isPackaged(item)) {
      final packageQty = double.tryParse(ctrls.qty.text.trim());
      final factor = _num(item['packaging_factor_snapshot']);
      if (packageQty == null || packageQty <= 0) {
        _qtyErrors[i] = 'Package quantity must be greater than zero.';
        ctrls.dirty = false;
        setState(() {});
        return;
      }
      if (!QuantityRule.isWhole(packageQty)) {
        _qtyErrors[i] =
            'Package quantity must be a whole number. Use the base unit for loose quantity.';
        ctrls.dirty = false;
        setState(() {});
        return;
      }
      if (factor <= 0) {
        _qtyErrors[i] =
            'This package conversion is invalid. Re-select the selling unit.';
        ctrls.dirty = false;
        setState(() {});
        return;
      }

      final baseQty = _round3(packageQty * factor);
      final baseRule = QuantityRule.fromProduct(item);
      if (!baseRule.allows(baseQty)) {
        _qtyErrors[i] = baseRule.message;
        ctrls.dirty = false;
        setState(() {});
        return;
      }

      final packagePrice = double.tryParse(ctrls.price.text.trim());
      final displayedDiscount = double.tryParse(ctrls.discount.text.trim());
      final discountType =
          (item['discount_type'] ?? 'percentage').toString();
      if (packagePrice == null || packagePrice < 0) {
        AppFeedback.warning(context, 'Enter a valid package sale price.');
        ctrls.dirty = false;
        return;
      }
      if (displayedDiscount == null || displayedDiscount < 0 ||
          (discountType == 'percentage' && displayedDiscount > 100) ||
          (discountType == 'fixed' &&
              displayedDiscount > packagePrice + 0.0004)) {
        AppFeedback.warning(
          context,
          discountType == 'fixed'
              ? 'Fixed discount cannot exceed the package sale price.'
              : 'Percentage discount must be between 0 and 100.',
        );
        ctrls.dirty = false;
        return;
      }

      item['packaging_quantity'] = packageQty;
      item['quantity'] = baseQty;
      item['packaging_unit_price'] = packagePrice;
      item['price'] = factor > 0 ? _round4(packagePrice / factor) : packagePrice;
      if (discountType == 'fixed') {
        item['packaging_discount_snapshot'] = displayedDiscount;
        item['discount_pct'] =
            factor > 0 ? _round4(displayedDiscount / factor) : displayedDiscount;
      } else {
        item.remove('packaging_discount_snapshot');
        item['discount_pct'] = displayedDiscount;
      }
      item['total'] = _displayLineTotal(
        item,
        price: packagePrice,
        qty: packageQty,
        discountPct: displayedDiscount,
        discountType: discountType,
      );

      final next = [...widget.items];
      next[i] = item;
      _qtyErrors.remove(i);
      ctrls.dirty = false;
      widget.onItemsChanged(next);
      setState(() {});
      return;
    }

    final qty = double.tryParse(ctrls.qty.text.trim()) ?? 0.0;

    // A negative quantity is a return intent, not a normal cart mutation.
    // Never commit the temporary negative value into parent state before the
    // async original-invoice linker succeeds; cancelling the dialog must leave
    // the cart exactly as it was. This also prevents parent/row-controller
    // desynchronisation and the RenderFlex/error-screen cascade it caused.
    if (qty < 0 && widget.onReturnLinkRequested != null) {
      ctrls.dirty = false;
      _startReturnLink(i, qty.abs());
      return;
    }

    final linkedReturn = item['original_sale_item_id'] != null;
    final price = linkedReturn ? _num(item['price']) : _num(ctrls.price.text);
    final disc = linkedReturn ? _num(item['discount_pct']) : _num(ctrls.discount.text);
    final discountType = (item['discount_type'] ?? 'percentage').toString();

    if (qty >= 0 && linkedReturn) {
      const returnKeys = <String>[
        'original_sale_id', 'original_sale_item_id', 'return_source_invoice',
        'return_reason', 'returnable_quantity', 'return_original_outstanding',
        'return_credit', 'return_merchandise_subtotal',
        'return_invoice_discount', 'return_tax', 'return_linked_quantity',
      ];
      for (final key in returnKeys) {
        item.remove(key);
      }
    }
    item['price'] = price;
    item['quantity'] = qty;
    item['discount_pct'] = disc;
    item['total'] = _displayLineTotal(
      item, price: price, qty: qty, discountPct: disc, discountType: discountType,
    );

    final rule = QuantityRule.fromProduct(item);
    if (rule.allows(qty)) {
      _qtyErrors.remove(i);
    } else {
      _qtyErrors[i] = rule.message;
    }

    final next = [...widget.items];
    next[i] = item;
    ctrls.dirty = false;
    widget.onItemsChanged(next);
    setState(() {});
  }

  Future<void> _startReturnLink(int i, double returnQuantity) async {
    if (_returnLinkInProgress.contains(i) ||
        i < 0 ||
        i >= widget.items.length ||
        widget.onReturnLinkRequested == null) {
      return;
    }

    _returnLinkInProgress.add(i);
    final ctrls = _rowCtrls[i];
    final originalQty = _num(widget.items[i]['quantity']);
    try {
      // Release the editor before opening the modal so its stale '-1' text
      // cannot remain the focused source of truth while parent state changes.
      ctrls?.qtyFocus.unfocus();
      final linked = await widget.onReturnLinkRequested!(i, returnQuantity);
      if (!mounted) return;

      final displayQty = linked ? -returnQuantity : originalQty;
      if (ctrls != null) {
        final text = _formatQty(displayQty);
        ctrls.qty.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        ctrls.dirty = false;
      }
      _qtyErrors.remove(i);
      setState(() {});
    } finally {
      _returnLinkInProgress.remove(i);
    }
  }

  /// Toggles the discount type for row [i] between 'percentage' and 'fixed',
  /// then recomputes the line total immediately with the new type.
  void _toggleDiscountType(int i) {
    if (i < 0 || i >= widget.items.length) return;
    if (widget.items[i]['original_sale_item_id'] != null) return;

    final next = [...widget.items];
    final item = Map<String, dynamic>.from(next[i]);
    final ctrls = _rowCtrls[i]!;
    final current = (item['discount_type'] ?? 'percentage').toString();
    final nextType = current == 'percentage' ? 'fixed' : 'percentage';
    var displayedDiscount = _num(ctrls.discount.text);
    final displayedPrice = _num(ctrls.price.text);

    // A number such as a fixed Rs. 480 cannot become 480%. Likewise a
    // percentage larger than a very small package price cannot become a valid
    // fixed amount. Reset only when the existing numeric value is invalid in
    // the newly selected semantic, rather than silently clipping money.
    if ((nextType == 'percentage' && displayedDiscount > 100) ||
        (nextType == 'fixed' && displayedDiscount > displayedPrice + 0.0004)) {
      displayedDiscount = 0;
      ctrls.discount.value = const TextEditingValue(
        text: '0.00',
        selection: TextSelection.collapsed(offset: 4),
      );
    }

    item['discount_type'] = nextType;
    if (_isPackaged(item)) {
      final factor = _num(item['packaging_factor_snapshot']);
      final packageQty = _num(ctrls.qty.text);
      final packagePrice = _num(ctrls.price.text);
      item['packaging_unit_price'] = packagePrice;
      if (factor > 0) item['price'] = _round4(packagePrice / factor);
      if (nextType == 'fixed') {
        item['packaging_discount_snapshot'] = displayedDiscount;
        item['discount_pct'] = factor > 0
            ? _round4(displayedDiscount / factor)
            : displayedDiscount;
      } else {
        item.remove('packaging_discount_snapshot');
        item['discount_pct'] = displayedDiscount;
      }
      item['total'] = _displayLineTotal(
        item,
        price: packagePrice,
        qty: packageQty,
        discountPct: displayedDiscount,
        discountType: nextType,
      );
    } else {
      item['discount_pct'] = displayedDiscount;
      final price = _num(ctrls.price.text);
      final qty = double.tryParse(ctrls.qty.text.trim()) ?? 0.0;
      item['total'] = _calcLineTotal(
        price: price,
        qty: qty,
        discountPct: displayedDiscount,
        discountType: nextType,
      );
    }

    next[i] = item;
    ctrls.dirty = false;
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
    final raw = p.raw ?? const <String, dynamic>{};
    next.add({
      'product_id': p.id,
      'name': p.name,
      'secondary_name': raw['secondary_name'],
      'cost_price': raw['cost_price'],
      'wholesale_price': raw['wholesale_price'],
      'price': p.tp,
      'discount_pct': discPct,
      'discount_type': discType,
      'quantity': 1.0,
      'total': _calcLineTotal(price: p.tp, qty: 1.0, discountPct: discPct, discountType: discType),
      ...SaleProfitCalculator.costFieldsFromProduct(raw),
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
          _displayLineTotal(
            it,
            price: _isPackaged(it)
                ? _num(it['packaging_unit_price'])
                : _num(it['price']),
            qty: _isPackaged(it)
                ? _num(it['packaging_quantity'])
                : _num(it['quantity']),
            discountPct: _isPackaged(it) &&
                    (it['discount_type'] ?? 'percentage').toString() == 'fixed'
                ? _num(it['packaging_discount_snapshot'])
                : _num(it['discount_pct'] ?? 0),
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
                  final lineTotal = _displayLineTotal(
                    item,
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
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (item['name'] ?? '').toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      if (item['original_sale_item_id'] == null &&
                                          widget.onEditSellingUnit != null &&
                                          (_isPackaged(item) || _hasPackagingChoices(item)))
                                        _buildSellingUnitMenu(i, item),
                                      if (item['original_sale_item_id'] != null)
                                        Text(
                                          '↩ Return • ${(item['return_source_invoice'] ?? '').toString()}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.warning),
                                        ),
                                    ],
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
                            enabled: item['original_sale_item_id'] == null,
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
                                  enabled: item['original_sale_item_id'] == null,
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
                            allowNegative: !_isPackaged(item),
                            rule: _isPackaged(item)
                                ? const QuantityRule(allowDecimal: false)
                                : _ruleFor(i),
                            errorText: _qtyErrors[i] ??
                                (_isPackaged(item)
                                    ? const QuantityRule(allowDecimal: false)
                                        .validateText(ctrls.qty.text)
                                    : _ruleFor(i).validateText(ctrls.qty.text)),
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
    final lineTotal = _displayLineTotal(
      item,
      price: _num(ctrls.price.text),
      qty: _num(ctrls.qty.text),
      discountPct: _num(ctrls.discount.text),
      discountType: compactDiscType,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRow = i),
      onExit: (_) {
        if (_hoveredRow == i) setState(() => _hoveredRow = null);
      },
      child: Container(
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (item['name'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        if (item['original_sale_item_id'] == null &&
                            widget.onEditSellingUnit != null &&
                            (_isPackaged(item) || _hasPackagingChoices(item)))
                          _buildSellingUnitMenu(i, item, compact: true),
                        if (item['original_sale_item_id'] != null)
                          Text(
                            '↩ Return • ${(item['return_source_invoice'] ?? '').toString()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.warning),
                          ),
                      ],
                    ),
                  ),
                  if (widget.onProfitInsight != null && item['original_sale_item_id'] == null && _hoveredRow == i)
                    SizedBox(
                      width: 24,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 28,
                        ),
                        tooltip: 'Profit insight',
                        icon: const Icon(
                          Icons.visibility_outlined,
                          size: 15,
                          color: AppTheme.primary,
                        ),
                        onPressed: () {
                          _rowDebounce[i]?.cancel();
                          _commitRow(i);
                          widget.onProfitInsight?.call(i);
                        },
                      ),
                    ),
                ],
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
              enabled: item['original_sale_item_id'] == null,
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
                    enabled: item['original_sale_item_id'] == null,
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
              allowNegative: !_isPackaged(item),
              compact: true,
              rule: _isPackaged(item)
                  ? const QuantityRule(allowDecimal: false)
                  : _ruleFor(i),
              errorText: _qtyErrors[i] ??
                  (_isPackaged(item)
                      ? const QuantityRule(allowDecimal: false)
                          .validateText(ctrls.qty.text)
                      : _ruleFor(i).validateText(ctrls.qty.text)),
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
  final bool enabled;
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
    this.enabled = true,
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
      enabled: enabled,
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

  bool dirty = false;

  _RowControllers({VoidCallback? onEditingBlur}) {
    if (onEditingBlur != null) {
      for (final focusNode in [priceFocus, discountFocus, qtyFocus]) {
        focusNode.addListener(() {
          if (!focusNode.hasFocus) onEditingBlur();
        });
      }
    }
  }

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
