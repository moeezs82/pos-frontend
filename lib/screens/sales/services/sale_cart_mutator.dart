import 'package:enterprise_pos/models/product_unit.dart' show QuantityRule;
import 'package:enterprise_pos/services/product_stock.dart';
import 'package:enterprise_pos/services/sale_pricing.dart';
import 'package:enterprise_pos/services/sale_profit.dart';

class SaleCartMutator {
  static double _roundTo(double value, int scale) {
    var factor = 1.0;
    for (var i = 0; i < scale; i++) {
      factor *= 10;
    }
    return (value * factor).roundToDouble() / factor;
  }

  static double _metaNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double lineTotal({
    required double price,
    required double qty,
    required double discPct,
    double extraDiscount = 0,
    String discountType = 'percentage',
  }) {
    final double t;
    if (discountType == 'fixed') {
      t = qty * (price - discPct);
    } else {
      final d = (discPct / 100.0).clamp(0.0, 100.0);
      t = qty * price * (1.0 - d);
    }
    final total = t - extraDiscount.clamp(0.0, double.infinity);
    return total.isFinite ? total : 0.0;
  }

  static double cartLineTotal(Map<String, dynamic> item) {
    final qty = _metaNum(item['quantity']);
    if (qty < 0 && item['original_sale_item_id'] != null) {
      return -_metaNum(item['return_credit']).abs();
    }

    if (item['packaging_id'] != null) {
      final packageQty = _metaNum(item['packaging_quantity']);
      final packagePrice = _metaNum(item['packaging_unit_price']);
      final gross = _roundTo(packageQty * packagePrice, 2);
      final discountType =
          (item['discount_type'] ?? 'percentage').toString().toLowerCase();
      final discount = discountType == 'fixed'
          ? _roundTo(
              packageQty * _metaNum(item['packaging_discount_snapshot']),
              2,
            )
          : _roundTo(
              gross *
                  (_metaNum(item['discount_pct']).clamp(0.0, 100.0) / 100.0),
              2,
            );
      return _roundTo(gross - discount - _metaNum(item['extra_discount']), 2);
    }

    return lineTotal(
      price: _metaNum(item['price']),
      qty: qty,
      discPct: _metaNum(item['discount_pct']),
      extraDiscount: _metaNum(item['extra_discount']),
      discountType: (item['discount_type'] ?? 'percentage').toString(),
    );
  }

  static void addOrIncrementProduct({
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> product,
    String? customerType,
  }) {
    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (productId == 0) return;
    final pickerAddQty =
        double.tryParse(product['_picker_add_qty']?.toString() ?? '');
    final addQty =
        pickerAddQty != null && pickerAddQty > 0 ? pickerAddQty : 1.0;

    final price = SalePricing.effectiveProductPrice(
      product,
      customerType: customerType,
    );
    final profitCostFields =
        SaleProfitCalculator.costFieldsFromProduct(product);

    final idx = items.indexWhere((it) {
      final existingId =
          int.tryParse(it['product_id']?.toString() ?? '') ?? 0;
      if (existingId != productId) return false;
      if (it['packaging_id'] != null) return false;
      final existingQty =
          double.tryParse(it['quantity']?.toString() ?? '') ?? 0.0;
      return existingQty >= 0;
    });

    if (idx != -1) {
      final existingQty =
          double.tryParse(items[idx]['quantity']?.toString() ?? '') ?? 0.0;
      final newQty = existingQty + addQty;
      final discPct =
          double.tryParse(items[idx]['discount_pct']?.toString() ?? '') ?? 0.0;
      final rowDiscType =
          (items[idx]['discount_type'] ?? 'percentage').toString();
      final rowPrice =
          double.tryParse(items[idx]['price']?.toString() ?? '') ?? price;
      items[idx]['quantity'] = newQty;
      items[idx].addAll(profitCostFields);
      items[idx].addAll(ProductStock.toTransactionRowFields(product));
      items[idx]['product_vendor_id'] =
          int.tryParse(product['vendor_id']?.toString() ?? '');
      final productVendorName = (product['vendor_name'] ?? '').toString().trim();
      items[idx]['product_vendor_name'] =
          productVendorName.isEmpty ? null : productVendorName;
      if ((product['secondary_name'] ?? '').toString().trim().isNotEmpty) {
        items[idx]['secondary_name'] = product['secondary_name'];
      }
      items[idx]['total'] = lineTotal(
        price: rowPrice,
        qty: newQty,
        discPct: discPct,
        discountType: rowDiscType,
      );
    } else {
      final scanDiscPct =
          double.tryParse(product['discount']?.toString() ?? '') ?? 0.0;
      final scanDiscType =
          (product['discount_type'] ?? 'percentage').toString();
      items.add({
        'product_id': productId,
        'product_vendor_id':
            int.tryParse(product['vendor_id']?.toString() ?? ''),
        'product_vendor_name': (product['vendor_name'] ?? '').toString().trim().isEmpty
            ? null
            : (product['vendor_name'] ?? '').toString().trim(),
        'name': product['name'],
        'secondary_name': product['secondary_name'],
        'cost_price': product['cost_price'],
        'wholesale_price': product['wholesale_price'],
        ...profitCostFields,
        ...ProductStock.toTransactionRowFields(product),
        'quantity': addQty,
        'price': price,
        'discount_pct': scanDiscPct,
        'discount_type': scanDiscType,
        'total': lineTotal(
          price: price,
          qty: addQty,
          discPct: scanDiscPct,
          discountType: scanDiscType,
        ),
        'packagings': product['packagings'],
        ...QuantityRule.fromProduct(product).toRowFields(),
      });
    }
  }

  static void applyPickedProduct({
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> product,
    required double qty,
    String? customerType,
  }) {
    final productId = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (productId == 0) return;

    final price = SalePricing.effectiveProductPrice(
      product,
      customerType: customerType,
    );
    final profitCostFields =
        SaleProfitCalculator.costFieldsFromProduct(product);

    final idx = items.indexWhere((it) {
      if ((int.tryParse(it['product_id']?.toString() ?? '') ?? 0) != productId) {
        return false;
      }
      if (it['packaging_id'] != null) return false;
      return (double.tryParse(it['quantity']?.toString() ?? '') ?? 0) >= 0;
    });

    if (idx != -1) {
      items[idx]['quantity'] = qty;
      items[idx].addAll(profitCostFields);
      items[idx].addAll(ProductStock.toTransactionRowFields(product));
      items[idx]['product_vendor_id'] =
          int.tryParse(product['vendor_id']?.toString() ?? '');
      final productVendorName = (product['vendor_name'] ?? '').toString().trim();
      items[idx]['product_vendor_name'] =
          productVendorName.isEmpty ? null : productVendorName;
      if ((product['secondary_name'] ?? '').toString().trim().isNotEmpty) {
        items[idx]['secondary_name'] = product['secondary_name'];
      }
      final discPct =
          double.tryParse(items[idx]['discount_pct']?.toString() ?? '') ?? 0.0;
      final existingDiscType =
          (items[idx]['discount_type'] ?? 'percentage').toString();
      final rowPrice =
          double.tryParse(items[idx]['price']?.toString() ?? '') ?? price;
      items[idx]['total'] = lineTotal(
        price: rowPrice,
        qty: qty,
        discPct: discPct,
        discountType: existingDiscType,
      );
      items[idx].addAll(QuantityRule.fromProduct(product).toRowFields());
    } else {
      final pickDiscPct =
          double.tryParse(product['discount']?.toString() ?? '') ?? 0.0;
      final pickDiscType =
          (product['discount_type'] ?? 'percentage').toString();
      items.add({
        'product_id': productId,
        'product_vendor_id':
            int.tryParse(product['vendor_id']?.toString() ?? ''),
        'product_vendor_name': (product['vendor_name'] ?? '').toString().trim().isEmpty
            ? null
            : (product['vendor_name'] ?? '').toString().trim(),
        'name': product['name'],
        'secondary_name': product['secondary_name'],
        'cost_price': product['cost_price'],
        'wholesale_price': product['wholesale_price'],
        ...profitCostFields,
        ...ProductStock.toTransactionRowFields(product),
        'quantity': qty,
        'price': price,
        'discount_pct': pickDiscPct,
        'discount_type': pickDiscType,
        'total': lineTotal(
          price: price,
          qty: qty,
          discPct: pickDiscPct,
          discountType: pickDiscType,
        ),
        'packagings': product['packagings'],
        ...QuantityRule.fromProduct(product).toRowFields(),
      });
    }
  }
}
