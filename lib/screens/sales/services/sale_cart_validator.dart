import 'package:enterprise_pos/api/core/api_client.dart' show ApiException;
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/utils/line_errors.dart';

class SaleCartValidator {
  static double _roundTo(double val, int places) {
    final mod = [1.0, 10.0, 100.0, 1000.0, 10000.0][places.clamp(0, 4)];
    return (val * mod).roundToDouble() / mod;
  }

  /// The first cart line whose quantity breaks its unit's rule, described in
  /// a way that points at the line — or null when every line is acceptable.
  ///
  /// This mirrors the backend's own pre-write guard (units.FirstViolation), so
  /// a sale that could only come back as a 422 never leaves the device — which
  /// matters most when the device is offline and the rejection would otherwise
  /// not surface until sync.
  static String? firstQuantityViolation(List<Map<String, dynamic>> items) {
    for (var i = 0; i < items.length; i++) {
      final row = items[i];
      final name = (row['name'] ?? 'item').toString();
      final qty = double.tryParse(row['quantity']?.toString() ?? '');
      if (qty == null) {
        return 'Line ${i + 1} ($name) has no valid quantity.';
      }
      if (row['packaging_id'] != null) {
        final packageQty =
            double.tryParse(row['packaging_quantity']?.toString() ?? '');
        final factor =
            double.tryParse(row['packaging_factor_snapshot']?.toString() ?? '');
        final linkedReturn = qty < 0 && row['original_sale_item_id'] != null;
        if (packageQty == null ||
            packageQty == 0 ||
            !QuantityRule.isWhole(packageQty)) {
          return 'Line ${i + 1} — $name: package quantity must be a non-zero whole number.';
        }
        if (linkedReturn && packageQty >= 0) {
          return 'Line ${i + 1} — $name: linked package return quantity must be negative.';
        }
        if (!linkedReturn && packageQty <= 0) {
          return 'Line ${i + 1} — $name: package quantity must be a positive whole number.';
        }
        if (factor == null || factor <= 0) {
          return 'Line ${i + 1} — $name: package conversion is invalid. Re-select the selling unit.';
        }
        final expectedBaseQty = _roundTo(packageQty * factor, 3);
        if ((expectedBaseQty - qty).abs() > 0.0005) {
          return 'Line ${i + 1} — $name: package quantity no longer matches its base-unit quantity. Re-select the selling unit.';
        }
      }
      final rule = QuantityRule.fromProduct(row);
      if (!rule.allows(qty)) {
        return 'Line ${i + 1} — $name: ${rule.message}';
      }
    }
    return null;
  }

  /// Reads a 422 bag and writes what it taught us back onto the cart.
  ///
  /// A `items.N.quantity` decimal rejection is the server stating that line
  /// N's unit does not allow a fraction — authoritative, and newer than
  /// whatever the line was carrying (a cache row from before the unit was
  /// changed, or no unit information at all). Recording it turns the field
  /// red and makes the client-side check catch the same mistake next time,
  /// instead of another round trip.
  static void applyServerLineErrors(
    List<Map<String, dynamic>> items,
    ApiException e,
  ) {
    for (final lineError in parseValidationBag(e.body?['errors'])) {
      final rule = lineError.assertedRule;
      if (rule == null) continue;
      final index = lineError.index;
      if (index < 0 || index >= items.length) continue;
      items[index]['unit_allow_decimal'] = false;
      if (rule.unitName.isNotEmpty) items[index]['unit_name'] = rule.unitName;
    }
  }

  /// Cashier-readable text for a rejection that will never succeed on retry.
  /// Field errors are listed with the cart line they belong to; anything else
  /// falls back to the server's own message.
  static String describeRejection(
    List<Map<String, dynamic>> items,
    ApiException e,
  ) {
    final lines = <String>[];
    flattenBag(e.body?['errors']).forEach((key, message) {
      final index =
          key.startsWith('items.') ? int.tryParse(key.split('.')[1]) : null;
      if (index != null && index >= 0 && index < items.length) {
        final name = (items[index]['name'] ?? 'item').toString();
        lines.add('Line ${index + 1} — $name: $message');
      } else {
        lines.add(message);
      }
    });
    if (lines.isEmpty) return 'Sale not saved: ${e.message}';
    return 'Sale not saved — please correct and try again.\n${lines.join('\n')}';
  }
}
