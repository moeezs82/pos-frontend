import 'dart:math';
import 'package:flutter/material.dart';

class SaleItemsSection extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onPickVendor;
  final Map<String, dynamic>? selectedVendor;
  final VoidCallback onAddItem;
  final void Function(Map item) onEditItem;
  final void Function(int itemId) onDeleteItem;

  const SaleItemsSection({
    super.key,
    required this.sale,
    required this.onPickVendor,
    required this.selectedVendor,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  // ---- helpers ----
  double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
  String _money(num v) => v.toStringAsFixed(2);

  double _lineTotal(Map i) {
    final price = _num(i['price']);
    final qty = _num(i['quantity']);
    final pct = _num(i['discount_pct'] ?? i['discount'] ?? 0);
    final d = (pct / 100.0).clamp(0, 1);
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
                ElevatedButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Item"),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ---- table header ----
            _TableHeader(),

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
                final productName = i['product']?['name'] ?? i['name'] ?? 'Product Deleted';
                final tp = _num(i['price']);
                final pct = _num(i['discount_pct'] ?? i['discount'] ?? 0);
                final qty = _num(i['quantity']);
                final total = _lineTotal(i);

                return InkWell(
                  onTap: () => onEditItem(i),
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
                                child: Text(
                                  productName.toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
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
                            // Discount (%)
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _money(pct),
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
                                  qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2),
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
          Expanded(flex: 2, child: Text("Discount (%)", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Qty", style: style, textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text("Total", style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}
