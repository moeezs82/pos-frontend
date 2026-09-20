import 'package:enterprise_pos/models/item_discount_display.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';

/// Cell content for the thermal receipt item table.
///
/// CounterIQ renders the same thermal receipt twice: ReceiptPreviewService
/// builds a PDF (used by the preview screen, Windows printer queues and
/// WhatsApp) and ThermalPrinterService writes raw ESC/POS for network
/// printers. Every string that lands in a table cell is produced here so the
/// two renderers cannot drift apart again.
///
/// Nothing in this class participates in totals, stock, valuation or
/// accounting. It is presentation only; [SaleReceiptItem] is already the
/// immutable print projection of a posted sale line.
class ThermalReceiptLayout {
  const ThermalReceiptLayout._();

  /// Whether the MRP column is printed.
  ///
  /// 58 mm paper cannot hold it: ESC/POS Font A gives 32 columns and
  /// SL + QTY + RATE + MRP + AMOUNT needs roughly 35.
  ///
  /// It is also suppressed when item discounts are hidden. MRP prints the
  /// gross unit price while RATE prints the net one, so showing both columns
  /// would expose the per-item discount that [ItemDiscountDisplay.hidden]
  /// exists to keep off the receipt.
  static bool showsMrp({
    required bool is58mm,
    required ItemDiscountDisplay discountDisplay,
  }) =>
      !is58mm && discountDisplay != ItemDiscountDisplay.hidden;

  static String money(num v) => v.toStringAsFixed(2);

  static String quantity(num v) =>
      (v % 1 == 0) ? v.toInt().toString() : v.toString();

  /// Quantity cell, e.g. `2 PCS` or `1 cr`.
  ///
  /// The package SIZE deliberately does not live here. The QTY column is
  /// only about eight characters wide once RATE, MRP and AMOUNT have taken
  /// their share of a 48-character line, so `1 cr [12 Piece]` used to be
  /// clipped mid-word. The size is printed by [packageSuffix] beside the
  /// product name instead, where the line can wrap. Package identity always
  /// comes from the sale-item snapshot, never from the product's current
  /// packaging configuration.
  static String qtyCell(SaleReceiptItem item) {
    final unit = item.hasPackagingSnapshot
        ? item.thermalUnitName
        : item.unitName.trim();
    return unit.isEmpty
        ? quantity(item.qty)
        : '${quantity(item.qty)} $unit';
  }

  /// Historical package contents shown after the product name, e.g.
  /// `[12 Piece]`. Empty when the line carries no packaging snapshot.
  static String packageSuffix(SaleReceiptItem item) {
    if (!item.hasPackagingSnapshot) return '';
    final size = item.packageSizeText;
    return size.isEmpty ? '' : '[$size]';
  }

  /// Net unit price after the item discount and the extra line discount.
  ///
  /// Derived for display only: CounterIQ has no separate net-rate field, and
  /// this value is never written back, re-multiplied into a total, or used in
  /// accounting. Because it is rounded to two decimals for printing,
  /// RATE x QTY can differ from AMOUNT by one minor unit on quantities that
  /// do not divide evenly. AMOUNT always prints the posted line total.
  static double netUnitRate(SaleReceiptItem item) {
    if (item.qty.abs() < 0.0000001) return item.price;
    return item.total / item.qty;
  }

  /// RATE cell. Without the MRP column the receipt keeps printing the unit
  /// price exactly as it did before this layout change.
  static String rateCell(SaleReceiptItem item, {required bool showMrp}) =>
      money(showMrp ? netUnitRate(item) : item.price);

  /// MRP cell: the gross unit price as entered on the sale.
  static String mrpCell(SaleReceiptItem item) => money(item.price);

  static String amountCell(SaleReceiptItem item) => money(item.total);

  /// Compact discount labels shown beside the item name.
  ///
  /// Only [ItemDiscountDisplay.compact] produces text here; detailed mode
  /// expands its own rows under the numbers and hidden mode prints nothing.
  static String discountSuffix(
    SaleReceiptItem item,
    ItemDiscountDisplay discountDisplay, {
    required bool is58mm,
  }) {
    if (discountDisplay != ItemDiscountDisplay.compact) return '';
    final parts = <String>[];
    if (item.hasDiscount) parts.add(item.compactDiscountLabel());
    if (item.hasExtraDiscount) {
      parts.add(item.compactExtraDiscountLabel(short: is58mm));
    }
    return parts.join(' ');
  }

  /// Operational (kitchen/packing) quantity line, e.g. `2 Carton (cr)`.
  static String operationalQtyCell(SaleReceiptItem item) {
    final unit = item.invoiceUnitName;
    return unit.isEmpty ? quantity(item.qty) : '${quantity(item.qty)} $unit';
  }

  /// 58 mm gives 32 characters per line, which cannot hold
  /// `Total Item : ( 3 )` and `Total Qty : ( 6 )` side by side, so the
  /// narrow roll uses the short form.
  static String totalItemsLabel(
    List<SaleReceiptItem> items, {
    bool is58mm = false,
  }) =>
      is58mm
          ? 'Items : ( ${items.length} )'
          : 'Total Item : ( ${items.length} )';

  /// Sums the printed quantities.
  ///
  /// When a sale mixes packaging units this adds cartons to pieces, which is
  /// what the counter staff asked for: it is a line-count aid, never an
  /// inventory figure. Stock and valuation stay base-unit driven.
  static String totalQtyLabel(
    List<SaleReceiptItem> items, {
    bool is58mm = false,
  }) {
    final total = items.fold<double>(0, (sum, it) => sum + it.qty);
    return is58mm
        ? 'Qty : ( ${quantity(total)} )'
        : 'Total Qty : ( ${quantity(total)} )';
  }
}
