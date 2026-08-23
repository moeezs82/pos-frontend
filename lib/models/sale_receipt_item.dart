/// Immutable print projection for one sale line.
///
/// [secondaryName] is optional alternate/local-language catalog metadata (for
/// example Arabic). It has no financial meaning and never participates in
/// totals, stock, WAC, or accounting.
class SaleReceiptItem {
  final String name;
  final String? secondaryName;
  final double price;
  final double qty;
  final double total;
  final String unitName;
  final double discountAmount;
  final String discountType;
  final double discountValue;

  const SaleReceiptItem({
    required this.name,
    this.secondaryName,
    required this.price,
    required this.qty,
    required this.total,
    this.unitName = '',
    this.discountAmount = 0,
    this.discountType = 'percentage',
    this.discountValue = 0,
  });

  String get effectiveSecondaryName => (secondaryName ?? '').trim();

  bool get hasDiscount => discountAmount > 0.004;

  String compactDiscountLabel() {
    if (!hasDiscount) return '';
    if (discountType.trim().toLowerCase() == 'percentage') {
      var pct = discountValue;
      if (pct <= 0 && price.abs() > 0 && qty.abs() > 0) {
        pct = (discountAmount / (price.abs() * qty.abs())) * 100;
      }
      final fixed = pct.toStringAsFixed(2);
      final text = fixed.endsWith('.00')
          ? fixed.substring(0, fixed.length - 3)
          : (fixed.endsWith('0') ? fixed.substring(0, fixed.length - 1) : fixed);
      return '-$text%';
    }
    return '-${discountAmount.toStringAsFixed(2)}';
  }

  String detailedDiscountLabel() {
    final compact = compactDiscountLabel();
    return compact.isEmpty ? '' : 'Discount $compact';
  }
}
