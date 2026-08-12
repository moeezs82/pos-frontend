/// Shared POS default-pricing rules.
///
/// Customer type only chooses the default price when a product is added.
/// It never rewrites an existing cart line and it never overrides a cashier's
/// explicit price edit.
class SalePricing {
  SalePricing._();

  static String normalizeCustomerType(dynamic raw) {
    final value = (raw ?? 'retail').toString().trim().toLowerCase();
    switch (value) {
      case 'wholesale':
      case 'reseller':
      case 'retail':
        return value;
      default:
        return 'retail';
    }
  }

  static bool isWholesale(dynamic customerType) =>
      normalizeCustomerType(customerType) == 'wholesale';

  static double effectiveProductPrice(
    Map<String, dynamic> product, {
    dynamic customerType,
  }) {
    final retail = _asDouble(product['price'] ?? product['tp']) ?? 0.0;
    if (!isWholesale(customerType)) return retail;

    final wholesale = _asDouble(product['wholesale_price']);
    // A blank/zero/negative wholesale price means "not configured". Falling
    // back to retail prevents an accidental zero-price sale.
    if (wholesale == null || wholesale <= 0) return retail;
    return wholesale;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
