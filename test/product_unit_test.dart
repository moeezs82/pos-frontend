import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_pos/models/product_unit.dart';

/// Units and the Allow Decimal rule, client side.
///
/// The backend is authoritative — these tests are about the till giving the
/// cashier an immediate, correct answer, and about never being STRICTER than
/// the server (which would block a legitimate sale with no way to explain it).
void main() {
  group('ProductUnit parsing', () {
    // Flutter tests 1 and 2.
    test('reads a real JSON boolean in both directions', () {
      expect(
        ProductUnit.fromJson({'id': 1, 'name': 'Kilogram', 'allow_decimal': true}).allowDecimal,
        isTrue,
      );
      expect(
        ProductUnit.fromJson({'id': 2, 'name': 'Piece', 'allow_decimal': false}).allowDecimal,
        isFalse,
      );
    });

    // Flutter test 3 — the backward-compatibility rule that keeps an old
    // offline cache usable.
    test('a missing allow_decimal defaults to true', () {
      final u = ProductUnit.fromJson({'id': 1, 'name': 'Legacy'});
      expect(u.allowDecimal, isTrue,
          reason: 'a cache written before this feature must keep behaving as it did');
    });

    // A value round-tripped through the local SQLite cache comes back as 1/0,
    // and older payloads may carry strings. All must mean the same thing.
    test('accepts the shapes the local cache and older payloads produce', () {
      for (final truthy in [true, 1, '1', 'true', 'TRUE', 'yes']) {
        expect(ProductUnit.parseBool(truthy, false), isTrue, reason: '$truthy');
      }
      for (final falsy in [false, 0, '0', 'false', 'FALSE', 'no']) {
        expect(ProductUnit.parseBool(falsy, true), isFalse, reason: '$falsy');
      }
    });

    test('an unparseable value falls back rather than throwing', () {
      // A parse failure must never take the till offline.
      expect(ProductUnit.parseBool('maybe', true), isTrue);
      expect(ProductUnit.parseBool(const [], false), isFalse);
      expect(ProductUnit.parseBool(null, true), isTrue);
    });

    test('label prefers the short name', () {
      expect(
        const ProductUnit(id: 1, name: 'Kilogram', shortName: 'kg').label,
        'kg',
      );
      expect(const ProductUnit(id: 1, name: 'Kilogram').label, 'Kilogram');
    });
  });

  group('QuantityRule.fromProduct', () {
    // Flutter test 4.
    test('reads the nested unit object the API returns', () {
      final rule = QuantityRule.fromProduct({
        'id': 9,
        'name': 'Loose Rice',
        'unit': {'id': 3, 'name': 'Kilogram', 'allow_decimal': true},
      });
      expect(rule.unitId, 3);
      expect(rule.unitName, 'Kilogram');
      expect(rule.allowDecimal, isTrue);
    });

    test('reads a flattened cache row', () {
      final rule = QuantityRule.fromProduct({
        'id': 9,
        'unit_id': 4,
        'unit_name': 'Piece',
        'unit_allow_decimal': 0,
      });
      expect(rule.unitId, 4);
      expect(rule.unitName, 'Piece');
      expect(rule.allowDecimal, isFalse);
    });

    // Flutter test 14 — an old cache with no unit information at all.
    test('a product with no unit information is permissive', () {
      expect(QuantityRule.fromProduct({'id': 9, 'name': 'Old'}).allowDecimal, isTrue);
      expect(QuantityRule.fromProduct(null).allowDecimal, isTrue);
      expect(QuantityRule.fromProduct(const {}).allowDecimal, isTrue);
    });

    test('a null nested unit is permissive, not a crash', () {
      final rule = QuantityRule.fromProduct({'id': 9, 'unit': null});
      expect(rule.allowDecimal, isTrue);
    });
  });

  group('QuantityRule.isWhole', () {
    test('recognises whole numbers however they are written', () {
      for (final q in [0, 1, 2, 10, -1, -5, 1.0, -5.000, 3.0000]) {
        expect(QuantityRule.isWhole(q), isTrue, reason: '$q');
      }
    });

    test('recognises fractions', () {
      for (final q in [1.5, 0.25, -1.5, 2.75, -0.001]) {
        expect(QuantityRule.isWhole(q), isFalse, reason: '$q');
      }
    });

    // This is the reason the check rounds to scale first. A quantity reached by
    // repeated increments, or recomputed from a line total, carries float
    // noise; a naive `q == q.truncate()` would reject a legitimate whole
    // number and the cashier would have no idea why.
    test('float representation noise does not make a number fractional', () {
      expect(QuantityRule.isWhole(2.9999999999999996), isTrue);
      expect(QuantityRule.isWhole(0.1 + 0.2 + 0.7), isTrue);
      var acc = 0.0;
      for (var i = 0; i < 10; i++) {
        acc += 0.1;
      }
      expect(acc == 1.0, isFalse, reason: 'sanity: the sum really is noisy');
      expect(QuantityRule.isWhole(acc * 3), isTrue);
    });

    test('NaN and infinity are never whole', () {
      expect(QuantityRule.isWhole(double.nan), isFalse);
      expect(QuantityRule.isWhole(double.infinity), isFalse);
    });
  });

  group('QuantityRule.allows', () {
    const piece = QuantityRule(unitId: 1, unitName: 'Piece', allowDecimal: false);
    const kilo = QuantityRule(unitId: 2, unitName: 'Kilogram', allowDecimal: true);

    // Flutter tests 5, 6, 7, 8, 9 — and the property underneath them all:
    // the rule judges GRANULARITY, never SIGN.
    test('a non-decimal unit takes whole numbers of either sign', () {
      for (final q in [2, 1.0, -1, -5.000, 0]) {
        expect(piece.allows(q), isTrue, reason: '$q');
      }
    });

    test('a non-decimal unit refuses fractions of either sign', () {
      for (final q in [1.5, 0.25, -1.5, -0.25, 2.75]) {
        expect(piece.allows(q), isFalse, reason: '$q');
      }
    });

    test('a decimal unit takes anything', () {
      for (final q in [1, 1.5, 0.25, -0.5, -2]) {
        expect(kilo.allows(q), isTrue, reason: '$q');
      }
    });

    test('the message names the unit so the cashier knows why', () {
      expect(piece.message, 'Decimal quantity is not allowed for unit "Piece".');
      expect(
        const QuantityRule(allowDecimal: false).message,
        'Decimal quantity is not allowed for the selected product unit.',
      );
    });

    test('the step never lets a whole-only unit land on a fraction', () {
      expect(piece.step, 1);
      expect(kilo.step, 0.5);
    });
  });

  group('QuantityRule.validateText', () {
    const piece = QuantityRule(unitId: 1, unitName: 'Piece', allowDecimal: false);

    test('accepts valid entries', () {
      expect(piece.validateText('2'), isNull);
      expect(piece.validateText('-1'), isNull);
      expect(piece.validateText(' 3 '), isNull);
    });

    // Flutter test 12 — this is what blocks a paste as well as typing, since
    // both land in the same controller.
    test('rejects a pasted or typed decimal', () {
      expect(piece.validateText('1.5'), piece.message);
      expect(piece.validateText('-1.5'), piece.message);
    });

    test('rejects nonsense', () {
      expect(piece.validateText('abc'), 'Enter a valid quantity.');
    });

    test('leaves empty input to the required-check', () {
      expect(piece.validateText(''), isNull);
      expect(piece.validateText(null), isNull);
    });
  });

  group('QuantityRule.format', () {
    test('a whole-only unit never shows a decimal point', () {
      const piece = QuantityRule(allowDecimal: false);
      expect(piece.format(2), '2');
      expect(piece.format(2.0), '2');
      expect(piece.format(-1), '-1');
    });

    test('a decimal unit shows the fraction without trailing zeros', () {
      const kilo = QuantityRule(allowDecimal: true);
      expect(kilo.format(1.5), '1.5');
      expect(kilo.format(0.25), '0.25');
      expect(kilo.format(3), '3');
    });
  });

  // Flutter test 13 — round-tripping a unit through the offline cache must not
  // change its meaning.
  group('offline round trip', () {
    test('toJson/fromJson preserves the rule', () {
      const original = ProductUnit(
        id: 7,
        name: 'Kilogram',
        shortName: 'kg',
        allowDecimal: true,
      );
      final restored = ProductUnit.fromJson(original.toJson());
      expect(restored, original);
    });

    test('a unit stored as 1/0 restores identically', () {
      final restored = ProductUnit.fromJson({
        'id': 7,
        'name': 'Piece',
        'short_name': 'pc',
        'allow_decimal': 0,
        'is_active': 1,
      });
      expect(restored.allowDecimal, isFalse);
      expect(restored.isActive, isTrue);
    });
  });
}
