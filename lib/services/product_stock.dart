/// Shared stock-display resolver for transaction product selectors.
///
/// Inventory truth lives in `product_stocks.quantity` on the backend. Current
/// `/products` responses expose that value both as `stocks[].quantity` and as
/// the compatibility root field `stock_qty`. Older/alternate payloads may use
/// `branch_stock`, `stock`, or `quantity_in_stock`, so transaction screens use
/// this one tolerant parser rather than each maintaining a slightly different
/// interpretation.
///
/// Offline catalogue rows intentionally do not expose a live quantity. Showing
/// a stale number is worse than showing no number at all, therefore rows marked
/// `_offline == true` always resolve to unknown stock.
class ProductStock {
  ProductStock._();

  static double? quantity(Map<String, dynamic>? product) {
    if (product == null || product['_offline'] == true) return null;

    // Cart/transaction rows preserve the live branch quantity they knew when
    // the product was selected. Presence of this key is intentional: a null
    // value means stock was unknown (for example an offline catalogue row),
    // so do not fall through to any older/stale compatibility field.
    if (product.containsKey('_transaction_stock_qty')) {
      return _asDouble(product['_transaction_stock_qty']);
    }

    final branchStock = product['branch_stock'];
    final fromBranch = _quantityFrom(branchStock);
    if (fromBranch != null) return fromBranch;

    final stocks = product['stocks'];
    if (stocks is List) {
      for (final row in stocks) {
        final value = _quantityFrom(row);
        if (value != null) return value;
      }
    }

    for (final key in const ['stock_qty', 'stock', 'quantity_in_stock']) {
      final value = _quantityFrom(product[key]);
      if (value != null) return value;
    }

    return null;
  }


  /// Fields to carry onto an in-progress Sale/Purchase line.
  ///
  /// Transaction rows intentionally keep only a DISPLAY copy of the live
  /// branch stock. Stock posting/validation remains server-authoritative; this
  /// value is never sent as inventory truth. Keeping it on the line lets the
  /// cart show the same stock the cashier saw in the product selector without
  /// another request per row.
  static Map<String, dynamic> toTransactionRowFields(
    Map<String, dynamic>? product,
  ) {
    final qty = quantity(product);
    final unit = unitLabel(product);
    return <String, dynamic>{
      '_transaction_stock_qty': qty,
      if (unit.isNotEmpty) 'unit_short_name': unit,
    };
  }

  static String unitLabel(Map<String, dynamic>? product) {
    if (product == null) return '';

    final nested = product['unit'];
    if (nested is Map) {
      final shortName = _text(nested['short_name']);
      if (shortName.isNotEmpty) return shortName;
      final name = _text(nested['name']);
      if (name.isNotEmpty) return name;
    }

    for (final key in const ['unit_short_name', 'unit_name']) {
      final value = _text(product[key]);
      if (value.isNotEmpty) return value;
    }

    return '';
  }

  static String formatQuantity(num quantity) {
    final value = quantity.toDouble();
    if (value == value.truncateToDouble()) return value.toStringAsFixed(0);

    // The stock schema stores four decimal places. Trim display-only trailing
    // zeroes without changing the value used by transaction validation.
    var text = value.toStringAsFixed(4);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }

  static String display(
    Map<String, dynamic>? product, {
    String unknown = '—',
  }) {
    final qty = quantity(product);
    if (qty == null) return unknown;
    final unit = unitLabel(product);
    final value = formatQuantity(qty);
    return unit.isEmpty ? value : '$value $unit';
  }

  static double? _quantityFrom(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      for (final key in const ['quantity', 'qty', 'in_stock', 'stock_qty']) {
        final parsed = _asDouble(raw[key]);
        if (parsed != null) return parsed;
      }
      return null;
    }
    return _asDouble(raw);
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}
