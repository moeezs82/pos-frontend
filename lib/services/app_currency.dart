import 'package:intl/intl.dart';

/// One branch-scoped money formatter for every UI surface.
///
/// The active branch updates [currency] through BranchProvider. Currency
/// symbols such as $, €, and £ are rendered before the amount; codes and
/// textual symbols such as KD, AED, and د.ك are rendered after it.
class AppCurrency {
  AppCurrency._();

  static String _currency = 'KD';

  static String get currency => _currency;

  static bool get usesLeadingSymbol => _isLeadingSymbol(_currency);

  /// Currency decorations for numeric input fields. Controller values remain
  /// plain numbers so API payloads and calculations are never formatted text.
  static String? inputPrefix({bool negative = false, bool positive = false}) {
    final sign = negative ? '-' : (positive ? '+' : '');
    if (usesLeadingSymbol) return '$sign$_currency ';
    return sign.isEmpty ? null : '$sign ';
  }

  static String? get inputSuffix => usesLeadingSymbol ? null : ' $_currency';

  static void configure(dynamic value) {
    final next = value?.toString().trim();
    _currency = next == null || next.isEmpty ? 'KD' : next;
  }

  static String format(dynamic value, {int decimalDigits = 2}) {
    final amount = _toNum(value);
    final absolute = amount.abs();
    final pattern = decimalDigits <= 0
        ? '#,##0'
        : '#,##0.${List.filled(decimalDigits, '0').join()}';
    final number = NumberFormat(pattern).format(absolute);
    final negative = amount < 0 ? '-' : '';

    if (_isLeadingSymbol(_currency)) {
      return '$negative$_currency$number';
    }
    return '$negative$number $_currency';
  }

  static String formatSigned(dynamic value, {int decimalDigits = 2}) {
    final amount = _toNum(value);
    final formatted = format(amount, decimalDigits: decimalDigits);
    return amount > 0 ? '+$formatted' : formatted;
  }

  static num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse((value ?? '0').toString().replaceAll(',', '')) ?? 0;
  }

  static bool _isLeadingSymbol(String value) => const {
        r'$',
        '€',
        '£',
        '¥',
        '₹',
        '₩',
        '₽',
        '₺',
        '₫',
        '฿',
        '₱',
      }.contains(value);
}

/// Drop-in object for report widgets that currently receive a formatter.
class AppMoneyFormatter {
  final int decimalDigits;

  const AppMoneyFormatter({this.decimalDigits = 2});

  String format(dynamic value) =>
      AppCurrency.format(value, decimalDigits: decimalDigits);
}
