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

  /// Immutable transaction packaging metadata used only for printing.
  ///
  /// These values come from the posted sale-item snapshot, never from the
  /// product's current packaging configuration. They have no inventory or
  /// accounting authority; [qty]/[price]/[total] are already the customer-
  /// facing print projection while stock/COGS remain base-unit driven.
  final String? packagingName;
  final String? packagingShortName;
  final double? packagingFactor;
  final String baseUnitName;

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
    this.packagingName,
    this.packagingShortName,
    this.packagingFactor,
    this.baseUnitName = '',
  });

  String _trimNumber(double value) {
    final fixed = value.toStringAsFixed(4);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String get effectivePackagingName => (packagingName ?? '').trim();

  String get effectivePackagingShortName =>
      (packagingShortName ?? '').trim();

  bool get hasPackagingSnapshot {
    final factor = packagingFactor ?? 0;
    return factor > 0 &&
        (effectivePackagingName.isNotEmpty ||
            effectivePackagingShortName.isNotEmpty ||
            unitName.trim().isNotEmpty);
  }

  /// Compact package identifier for thermal lines (e.g. `cr`, `bx`).
  /// User-defined short names are used as-is; CounterIQ never invents an
  /// abbreviation for a package.
  String get thermalUnitName {
    if (!hasPackagingSnapshot) return unitName.trim();
    if (effectivePackagingShortName.isNotEmpty) {
      return effectivePackagingShortName;
    }
    if (effectivePackagingName.isNotEmpty) return effectivePackagingName;
    return unitName.trim();
  }

  /// Full package identity for paged invoices and packing tickets, for example
  /// `Carton (cr)`. If the user did not configure a short name, only the
  /// package name is rendered.
  String get invoiceUnitName {
    if (!hasPackagingSnapshot) return unitName.trim();
    final name = effectivePackagingName;
    final short = effectivePackagingShortName;
    if (name.isNotEmpty &&
        short.isNotEmpty &&
        name.toLowerCase() != short.toLowerCase()) {
      return '$name ($short)';
    }
    if (name.isNotEmpty) return name;
    if (short.isNotEmpty) return short;
    return unitName.trim();
  }

  /// Historical contents of one package, e.g. `50 Piece`.
  String get packageSizeText {
    if (!hasPackagingSnapshot) return '';
    final factor = packagingFactor ?? 0;
    if (factor <= 0) return '';
    final base = baseUnitName.trim();
    return base.isEmpty ? _trimNumber(factor) : '${_trimNumber(factor)} $base';
  }

  /// Historical conversion used by paged invoices / audit-friendly prints,
  /// e.g. `1 Carton = 50 Piece`.
  String get packageConversionText {
    if (!hasPackagingSnapshot) return '';
    final package = effectivePackagingName.isNotEmpty
        ? effectivePackagingName
        : thermalUnitName;
    final size = packageSizeText;
    if (package.isEmpty || size.isEmpty) return '';
    return '1 $package = $size';
  }

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
    var fixedPerUnit = discountValue;
    if (fixedPerUnit <= 0 && qty.abs() > 0) {
      fixedPerUnit = discountAmount / qty.abs();
    }
    if (fixedPerUnit <= 0) fixedPerUnit = discountAmount;
    return '-${fixedPerUnit.toStringAsFixed(2)}';
  }

  String detailedDiscountLabel() {
    final compact = compactDiscountLabel();
    return compact.isEmpty ? '' : 'Discount $compact';
  }
}
