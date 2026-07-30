import 'package:flutter_test/flutter_test.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/utils/line_errors.dart';

/// The exact sentence the Go backend produces (units.Rule.Message), quoted
/// unit and all. If this string ever changes on the server, these tests are
/// the ones that must fail first.
const _serverDecimalMessage =
    'Decimal quantity is not allowed for unit "Piece".';

void main() {
  group('parseValidationBag', () {
    test('maps items.N.field keys back to their line index', () {
      final errors = {
        'items.0.quantity': [_serverDecimalMessage],
        'items.2.received_qty': ['Decimal quantity is not allowed for unit "Box".'],
      };

      final parsed = parseValidationBag(errors);

      expect(parsed.length, 2);
      expect(parsed[0].index, 0);
      expect(parsed[0].field, 'quantity');
      expect(parsed[0].message, _serverDecimalMessage);
      expect(parsed[1].index, 2);
      expect(parsed[1].field, 'received_qty');
    });

    test('ignores keys that are not line-scoped', () {
      final parsed = parseValidationBag({
        'customer_id': ['The selected customer id is invalid.'],
        'items.1.quantity': [_serverDecimalMessage],
      });

      expect(parsed.length, 1);
      expect(parsed.single.index, 1);
    });

    test('tolerates a bare string instead of a list', () {
      final parsed = parseValidationBag({'items.0.quantity': _serverDecimalMessage});
      expect(parsed.single.message, _serverDecimalMessage);
    });

    test('joins multiple messages for one field', () {
      final parsed = parseValidationBag({
        'items.0.quantity': ['First problem.', 'Second problem.'],
      });
      expect(parsed.single.message, 'First problem. Second problem.');
    });

    test('returns empty for null, a non-map, and an empty bag', () {
      expect(parseValidationBag(null), isEmpty);
      expect(parseValidationBag('not a bag'), isEmpty);
      expect(parseValidationBag(<String, dynamic>{}), isEmpty);
    });

    test('skips a malformed index rather than throwing', () {
      expect(parseValidationBag({'items.x.quantity': ['nope']}), isEmpty);
      expect(parseValidationBag({'items.0': ['nope']}), isEmpty);
    });
  });

  group('storage round trip', () {
    test('what the sync service writes is what the review screen reads', () {
      final bag = {
        'items.0.quantity': [_serverDecimalMessage],
        'items.1.quantity': ['The items.1.quantity field is required.'],
      };

      final stored = formatBagForStorage(bag);
      // Prefixed with the humanized sentence, exactly as OfflineSyncService
      // stores it.
      final lastError = 'The server rejected this sale: $_serverDecimalMessage\n$stored';

      final parsed = parseStoredLineErrors(lastError);

      expect(parsed.length, 2);
      expect(parsed[0].index, 0);
      expect(parsed[0].message, _serverDecimalMessage);
      expect(parsed[1].index, 1);
    });

    test('the humanized prose line alone yields nothing to correct', () {
      final parsed = parseStoredLineErrors(
          'The server rejected this sale: The given data was invalid.');
      expect(parsed, isEmpty);
    });

    test('handles null and empty stored errors', () {
      expect(parseStoredLineErrors(null), isEmpty);
      expect(parseStoredLineErrors(''), isEmpty);
    });

    test('a message containing a colon survives the round trip', () {
      final bag = {
        'items.0.quantity': ['Rejected: value out of range.'],
      };
      final parsed = parseStoredLineErrors(formatBagForStorage(bag));
      expect(parsed.single.message, 'Rejected: value out of range.');
    });
  });

  group('assertedRule', () {
    test('a decimal rejection asserts a whole-number rule naming the unit', () {
      final error = parseValidationBag({
        'items.0.quantity': [_serverDecimalMessage],
      }).single;

      final rule = error.assertedRule;

      expect(rule, isNotNull);
      expect(rule!.allowDecimal, isFalse);
      expect(rule.unitName, 'Piece');
      expect(rule.allows(2), isTrue);
      expect(rule.allows(-1), isTrue, reason: 'the rule is granularity, not sign');
      expect(rule.allows(1.5), isFalse);
    });

    test('the client message matches the server sentence verbatim', () {
      // Both sides must say the same thing, or the cashier sees one sentence
      // in the field and a different one in the toast for the same problem.
      const rule = QuantityRule(unitName: 'Piece', allowDecimal: false);
      expect(rule.message, _serverDecimalMessage);
    });

    test('a rejection with no named unit still asserts the rule', () {
      final error = parseValidationBag({
        'items.0.quantity': [
          'Decimal quantity is not allowed for the selected product unit.'
        ],
      }).single;

      expect(error.assertedRule, isNotNull);
      expect(error.assertedRule!.unitName, isEmpty);
    });

    test('any other error asserts nothing — it is not about granularity', () {
      final error = parseValidationBag({
        'items.0.quantity': ['The items.0.quantity field is required.'],
      }).single;

      expect(error.assertedRule, isNull);
    });
  });

  group('display', () {
    test('a quantity complaint is shown without a redundant field name', () {
      const error =
          LineError(index: 0, field: 'quantity', message: 'Too many.');
      expect(error.display, 'Too many.');
    });

    test('any other field is named', () {
      const error =
          LineError(index: 0, field: 'received_qty', message: 'Too many.');
      expect(error.display, 'received_qty: Too many.');
    });
  });
}
