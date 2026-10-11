import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/services/app_currency.dart';

/// Presentation-only helpers shared by every receipt/invoice renderer (the PDF
/// templates and the raw ESC/POS printer), so the optional shop website and the
/// "You Save" line behave identically on every design template.
///
/// Nothing here participates in totals, stock or accounting: it only reads the
/// already-posted discount figures that the receipt is printing anyway.
class ReceiptExtras {
  const ReceiptExtras._();

  /// Key inside the receipt `meta` map that carries the branch's optional
  /// website. Passing it through `meta` keeps every existing renderer
  /// signature unchanged.
  static const websiteMetaKey = 'shop_website';

  /// The website to print under the shop name, or null when none is set.
  static String? websiteFrom(Map<String, dynamic>? meta) {
    final value = (meta?[websiteMetaKey] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  /// Everything the customer saved on this bill: the invoice-level discount
  /// plus each line's item discount and extra discount. Rounded to 2 decimals;
  /// 0 when no discount was applied (the "You Save" line is then hidden).
  static double totalSavings({
    required List<SaleReceiptItem> items,
    required double invoiceDiscount,
    bool includeItemDiscounts = true,
  }) {
    var total = invoiceDiscount > 0 ? invoiceDiscount : 0.0;
    if (includeItemDiscounts) total += itemDiscountTotal(items);
    return (total * 100).round() / 100;
  }

  /// Sum of every line's item discount and extra discount (money, not %).
  /// Line totals on the receipt are already net of these, so adding this back
  /// to the posted subtotal gives the pre-discount (gross) subtotal.
  static double itemDiscountTotal(List<SaleReceiptItem> items) {
    var total = 0.0;
    for (final item in items) {
      if (item.hasDiscount) total += item.discountAmount.abs();
      if (item.hasExtraDiscount) total += item.extraDiscountAmount.abs();
    }
    return (total * 100).round() / 100;
  }

  /// Amount text for the "You Save" line, e.g. `Rs. 120.00`. Uses the branch
  /// currency; PKR/Rs render as `Rs.` and leading-symbol currencies as `$120.00`.
  static String money(double amount) {
    final number = amount.toStringAsFixed(2);
    final currency = AppCurrency.currency.trim();
    final upper = currency.toUpperCase();
    if (currency.isEmpty || upper == 'PKR' || upper == 'RS' || upper == 'RS.') {
      return 'Rs. $number';
    }
    if (AppCurrency.usesLeadingSymbol) return '$currency$number';
    return '$currency $number';
  }
}
