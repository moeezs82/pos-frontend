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

  const SaleReceiptItem({
    required this.name,
    this.secondaryName,
    required this.price,
    required this.qty,
    required this.total,
    this.unitName = '',
    this.discountAmount = 0,
  });

  String get effectiveSecondaryName => (secondaryName ?? '').trim();
}
