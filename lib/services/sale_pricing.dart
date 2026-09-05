import 'package:enterprise_pos/models/product_packaging.dart';

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


  /// Cashier-facing selling price for one product-specific package.
  ///
  /// Wholesale follows the same safe fallback contract as the base product:
  /// an explicit package wholesale override wins; otherwise an actually
  /// configured base wholesale price is multiplied by the package factor; if
  /// wholesale is unconfigured, fall back to the package retail price rather
  /// than creating a zero-price sale.
  static double effectivePackagingPrice(
    Map<String, dynamic> product,
    ProductPackaging packaging, {
    dynamic customerType,
  }) {
    final retailBase = _asDouble(product['price'] ?? product['tp']) ?? 0.0;
    final retailPackage = packaging.effectiveRetailPrice(retailBase);
    if (!isWholesale(customerType)) return retailPackage;

    if (packaging.wholesalePrice != null) {
      return packaging.wholesalePrice!;
    }
    final wholesaleBase = _asDouble(product['wholesale_price']);
    if (wholesaleBase == null || wholesaleBase <= 0) return retailPackage;
    return wholesaleBase * packaging.baseQuantity;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
