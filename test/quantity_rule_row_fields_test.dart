import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_pos/models/product_unit.dart';

/// The rule has to survive being stamped onto a cart line and read back, and
/// the line is a plain map that travels through the picker, the cart, the
/// offline queue and the local SQLite cache. These tests pin the round trip in
/// every shape it actually takes.
void main() {
  group('toRowFields round trip', () {
    test('a whole-number rule survives being stamped onto a line', () {
      const rule =
          QuantityRule(unitId: 3, unitName: 'Piece', allowDecimal: false);

      final line = <String, dynamic>{
        'product_id': 20,
        'quantity': 1.0,
        ...rule.toRowFields(),
      };

      final readBack = QuantityRule.fromProduct(line);
      expect(readBack, rule);
      expect(readBack.allows(1.5), isFalse);
    });

    test('a decimal rule survives too', () {
      const rule = QuantityRule(unitId: 4, unitName: 'Kg', allowDecimal: true);
      final line = <String, dynamic>{...rule.toRowFields()};
      expect(QuantityRule.fromProduct(line), rule);
      expect(QuantityRule.fromProduct(line).allows(1.5), isTrue);
    });

    test('stamping does not disturb the rest of the line', () {
      const rule = QuantityRule(unitId: 1, unitName: 'Piece', allowDecimal: false);
      final line = <String, dynamic>{
        'product_id': 20,
        'price': 100.0,
        'discount_pct': 5.0,
        'quantity': 2.0,
        ...rule.toRowFields(),
      };

      expect(line['product_id'], 20);
      expect(line['price'], 100.0);
      expect(line['discount_pct'], 5.0);
      expect(line['quantity'], 2.0);
    });
  });

  group('product shapes the cart is built from', () {
    test('a live /products row (nested unit object)', () {
      final product = <String, dynamic>{
        'id': 20,
        'name': 'Shirt',
        'unit_id': 1,
        'unit': {
          'id': 1,
          'name': 'Piece',
          'short_name': 'pc',
          'allow_decimal': false,
        },
      };

      final rule = QuantityRule.fromProduct(product);
      expect(rule.unitId, 1);
      expect(rule.unitName, 'Piece');
      expect(rule.allowDecimal, isFalse);
    });

    test('a product with unit: null is decimal-allowed, the pre-units default',
        () {
      final rule = QuantityRule.fromProduct({'id': 20, 'unit': null});
      expect(rule.allowDecimal, isTrue);
      expect(rule.unitId, isNull);
    });

    test('a local cache row stores 1/0, not a JSON boolean', () {
      // sqflite has no boolean type; catalog_cache_service writes an int.
      final cacheRow = <String, dynamic>{
        'id': 20,
        'unit_id': 1,
        'unit_name': 'Piece',
        'unit_allow_decimal': 0,
      };

      final rule = QuantityRule.fromProduct(cacheRow);
      expect(rule.allowDecimal, isFalse);
      expect(rule.unitName, 'Piece');
    });

    test('a cache row from before the unit columns existed stays permissive',
        () {
      // ALTER TABLE ... ADD COLUMN leaves NULL on every pre-existing row. A
      // till that has not refreshed yet must keep taking the quantities it
      // took yesterday; the backend re-validates on sync.
      final preUpgradeRow = <String, dynamic>{
        'id': 20,
        'name': 'Shirt',
        'unit_id': null,
        'unit_name': null,
        'unit_allow_decimal': null,
      };

      expect(QuantityRule.fromProduct(preUpgradeRow).allowDecimal, isTrue);
    });

    test('a queued offline line with no unit information at all', () {
      // buildSalePayload keeps only product_id/quantity/discount_pct/price,
      // so a line rebuilt from a queued payload carries no rule.
      final payloadLine = <String, dynamic>{
        'product_id': 20,
        'quantity': 1.5,
        'discount_pct': 0.0,
        'price': 100.0,
      };

      final rule = QuantityRule.fromProduct(payloadLine);
      expect(rule.allowDecimal, isTrue);
      expect(rule.allows(1.5), isTrue);
    });
  });

  group('the rule is granularity, not sign', () {
    const whole = QuantityRule(unitName: 'Piece', allowDecimal: false);

    test('a negative whole quantity stays valid (inline return)', () {
      expect(whole.allows(-1), isTrue);
      expect(whole.validateText('-1'), isNull);
    });

    test('a negative fractional quantity does not', () {
      expect(whole.allows(-1.5), isFalse);
      expect(whole.validateText('-1.5'), whole.message);
    });

    test('an empty field is left to the required-check, not rejected here', () {
      expect(whole.validateText(''), isNull);
      expect(whole.validateText(null), isNull);
    });

    test('unparseable text is reported as such', () {
      expect(whole.validateText('abc'), 'Enter a valid quantity.');
    });

    test('float noise from repeated stepping is not treated as a fraction', () {
      // 0.1 + 0.2 == 0.30000000000000004; three "+" taps on a whole unit must
      // not become a rule violation.
      var q = 0.0;
      for (var i = 0; i < 3; i++) {
        q += 1.0;
      }
      expect(whole.allows(q), isTrue);
      expect(whole.allows(2.9999999999999996), isTrue);
    });
  });
}
