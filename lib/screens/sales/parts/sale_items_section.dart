import 'dart:math';
import 'package:flutter/material.dart';
import 'package:enterprise_pos/services/app_currency.dart';

class SaleItemsSection extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback? onPickVendor;
  final Map<String, dynamic>? selectedVendor;
  final VoidCallback? onAddItem;
  final void Function(Map item)? onEditItem;
  final void Function(int itemId)? onDeleteItem;
  final bool editable;

  const SaleItemsSection({
    super.key,
    required this.sale,
    this.onPickVendor,
    this.selectedVendor,
    this.onAddItem,
    this.onEditItem,
    this.onDeleteItem,
    this.editable = true,
  });

  // ---- helpers ----
  double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
  String _money(num v) => AppCurrency.format(v);

  bool _isPackaged(Map i) => i['packaging_id'] != null;

  String _qtyText(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 3);

  double _lineTotal(Map i) {
    // The backend-stored total is authoritative, especially for packaged
    // lines where package price / factor may be a repeating decimal.
    if (i['total'] != null) return _num(i['total']);

    if (_isPackaged(i)) {
      final packagePrice = _num(i['packaging_unit_price']);
      final packageQty = _num(i['packaging_quantity']);
      final discountVal = (i['discount_type'] ?? 'percentage').toString() == 'fixed'
          ? _num(i['packaging_discount_snapshot'])
          : _num(i['discount_pct'] ?? i['discount'] ?? 0);
      final discountType = (i['discount_type'] ?? 'percentage').toString();
      final gross = packagePrice * packageQty;
      if (discountType == 'fixed') {
        return max(0.0, gross - (packageQty * discountVal));
      }
      final d = (discountVal / 100.0).clamp(0.0, 1.0);
      return max(0.0, gross * (1 - d));
    }

    final price        = _num(i['price']);
    final qty          = _num(i['quantity']);
    final discountVal  = _num(i['discount_pct'] ?? i['discount'] ?? 0);
    final discountType = (i['discount_type'] ?? 'percentage').toString();

    if (discountType == 'fixed') {
      return max(0.0, qty * (price - discountVal));
    }
    final d = (discountVal / 100.0).clamp(0.0, 1.0);
    return max(0.0, qty * price * (1 - d));
  }


  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(sale['items'] as List);
    final t = Theme.of(context);

    final subtotal = items.fold<double>(0, (s, i) => s + _lineTotal(i));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ---- header bar ----
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
                if (editable && onAddItem != null)
                  ElevatedButton.icon(
                    onPressed: onAddItem,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Item"),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ---- table header ----
            _TableHeader(editable: editable),

            const Divider(height: 8),

            // ---- table rows ----
            if (items.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    "No items added",
                    style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
                  ),
                ),
              )
            else
              ...items.map((i) {
                final productName  = i['product']?['name'] ?? i['name'] ?? 'Product Deleted';
                final packaged = _isPackaged(i);
                final tp = packaged
                    ? _num(i['packaging_unit_price'])
                    : _num(i['price']);
                final discountType =
                    (i['discount_type'] ?? 'percentage').toString();
                final discountVal = packaged && discountType == 'fixed'
                    ? _num(i['packaging_discount_snapshot'])
                    : _num(i['discount_pct'] ?? i['discount'] ?? 0);
                final qty = packaged
                    ? _num(i['packaging_quantity'])
                    : _num(i['quantity']);
                final total = _lineTotal(i);
                final packageName = (i['packaging_short_name_snapshot'] ??
                        i['packaging_name_snapshot'] ??
                        '')
                    .toString()
                    .trim();
                final baseQty = _num(i['quantity']);
                final product = i['product'];
                final unitRaw = i['unit_name'] ??
                    i['unit_symbol'] ??
                    (product is Map ? product['unit'] : null);
                final baseUnit = unitRaw is Map
                    ? (unitRaw['symbol'] ?? unitRaw['name'] ?? '').toString()
                    : (unitRaw ?? '').toString();

                return InkWell(
                  onTap: editable && onEditItem != null
                      ? () => onEditItem!(i)
                      : null,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            // Product name
                            Expanded(
                              flex: 6,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      productName.toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    if (packaged)
                                      Text(
                                        '$packageName • ${_qtyText(baseQty)}${baseUnit.isEmpty ? ' base units' : ' $baseUnit'} stock/COGS',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: t.hintColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            // T.P
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _money(tp),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                            // Discount
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  discountType == 'fixed'
                                      ? '${_money(discountVal)} fx'
                                      : '${discountVal.toStringAsFixed(discountVal % 1 == 0 ? 0 : 2)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                            // Qty
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  packaged && packageName.isNotEmpty
                                      ? '${_qtyText(qty)} $packageName'
                                      : _qtyText(qty),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                            // Total
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _money(total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 8),
                    ],
                  ),
                );
              }).toList(),

            // ---- footer subtotal ----
            if (items.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "Subtotal: ${_money(subtotal)}",
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

class _TableHeader extends StatelessWidget {
  final bool editable;
  const _TableHeader({required this.editable});

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
          const Expanded(flex: 6, child: Text("Product")),
          Expanded(flex: 2, child: Text("T.P", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Discount", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Qty", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Total", style: style, textAlign: TextAlign.right)),
          if (editable) const SizedBox(width: 44),
        ],
      ),
    );
  }
}
