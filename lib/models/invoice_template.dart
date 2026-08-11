/// Predefined customer receipt/invoice layouts.
///
/// Thermal templates keep their existing mm58/mm80 behaviour. The paged
/// [standardInvoice] layout uses a branch-configured A4/A5/Letter page size and
/// is intended for PDF or an installed Windows printer, never raw ESC/POS TCP.
enum InvoiceTemplate {
  standard,
  compact,
  kitchen,
  standardInvoice;

  String get value => switch (this) {
        InvoiceTemplate.standard => 'standard',
        InvoiceTemplate.compact => 'compact',
        InvoiceTemplate.kitchen => 'kitchen',
        InvoiceTemplate.standardInvoice => 'standard_invoice',
      };

  String get label => switch (this) {
        InvoiceTemplate.standard => 'Standard Receipt',
        InvoiceTemplate.compact => 'Compact Receipt',
        InvoiceTemplate.kitchen => 'Kitchen Ticket',
        InvoiceTemplate.standardInvoice => 'Standard Invoice',
      };

  String get description => switch (this) {
        InvoiceTemplate.standard =>
          'Full 80 mm customer receipt with shop details, customer info, totals and footer.',
        InvoiceTemplate.compact =>
          'Narrow 58 mm customer receipt for small thermal printers.',
        InvoiceTemplate.kitchen =>
          'Operational secondary ticket for kitchen, packing or preparation.',
        InvoiceTemplate.standardInvoice =>
          'Professional paged invoice for normal printers. Supports A4, A5 and Letter paper, discount column, payments, optional logo and QR code.',
      };

  bool get isPaged => this == InvoiceTemplate.standardInvoice;
  bool get isCustomerFacing => this != InvoiceTemplate.kitchen;
  bool get supportsRawNetwork => !isPaged;

  /// Thermal paper code. Paged invoices use the configured paper size instead.
  String get paperWidthCode => switch (this) {
        InvoiceTemplate.compact => 'mm58',
        InvoiceTemplate.standardInvoice => 'a4',
        _ => 'mm80',
      };

  InvoiceSections get sections => switch (this) {
        InvoiceTemplate.standard => const InvoiceSections(
            header: true,
            customer: true,
            totalsBreakdown: true,
            footer: true,
          ),
        InvoiceTemplate.compact => const InvoiceSections(
            header: true,
            customer: false,
            totalsBreakdown: true,
            footer: false,
          ),
        InvoiceTemplate.kitchen => const InvoiceSections(
            header: false,
            customer: true,
            itemPrices: true,
            totalsBreakdown: false,
            footer: false,
          ),
        InvoiceTemplate.standardInvoice => const InvoiceSections(
            header: true,
            customer: true,
            totalsBreakdown: true,
            footer: true,
          ),
      };

  static InvoiceTemplate fromValue(String? v) {
    return InvoiceTemplate.values.firstWhere(
      (t) => t.value == v,
      orElse: () => InvoiceTemplate.standard,
    );
  }
}

class InvoiceSections {
  final bool header;
  final bool customer;
  final bool itemPrices;
  final bool totalsBreakdown;
  final bool footer;

  const InvoiceSections({
    required this.header,
    required this.customer,
    this.itemPrices = true,
    required this.totalsBreakdown,
    required this.footer,
  });

  factory InvoiceSections.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    final fallback = InvoiceTemplate.standard.sections;
    return InvoiceSections(
      header: flag('header', fallback.header),
      customer: flag('customer', fallback.customer),
      itemPrices: flag('item_prices', fallback.itemPrices),
      totalsBreakdown:
          flag('totals_breakdown', fallback.totalsBreakdown),
      footer: flag('footer', fallback.footer),
    );
  }
}
