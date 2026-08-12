/// Predefined customer receipt/invoice layouts.
///
/// Thermal templates keep their existing mm58/mm80 behaviour. Paged invoice
/// layouts use a branch-configured A4/A5/Letter page size and are intended for
/// PDF or an installed Windows printer, never raw ESC/POS TCP.
enum InvoiceTemplate {
  standard,
  compact,
  kitchen,
  standardInvoice,
  arabicThermal,
  arabicStandardInvoice;

  String get value => switch (this) {
        InvoiceTemplate.standard => 'standard',
        InvoiceTemplate.compact => 'compact',
        InvoiceTemplate.kitchen => 'kitchen',
        InvoiceTemplate.standardInvoice => 'standard_invoice',
        InvoiceTemplate.arabicThermal => 'arabic_thermal',
        InvoiceTemplate.arabicStandardInvoice => 'arabic_standard_invoice',
      };

  String get label => switch (this) {
        InvoiceTemplate.standard => 'Standard Receipt',
        InvoiceTemplate.compact => 'Compact Receipt',
        InvoiceTemplate.kitchen => 'Kitchen Ticket',
        InvoiceTemplate.standardInvoice => 'Standard Invoice',
        InvoiceTemplate.arabicThermal => 'Arabic Thermal Receipt',
        InvoiceTemplate.arabicStandardInvoice => 'Arabic Standard Invoice',
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
        InvoiceTemplate.arabicThermal =>
          'Arabic-first bilingual customer receipt. Arabic labels and local product names print first, with English secondary. Supports configurable 58 mm or 80 mm thermal paper.',
        InvoiceTemplate.arabicStandardInvoice =>
          'Arabic-first bilingual paged invoice for A4, A5 and Letter printers. Values print once with bilingual labels; Arabic product names appear above English names.',
      };

  bool get isPaged =>
      this == InvoiceTemplate.standardInvoice ||
      this == InvoiceTemplate.arabicStandardInvoice;

  bool get isArabicFirst =>
      this == InvoiceTemplate.arabicThermal ||
      this == InvoiceTemplate.arabicStandardInvoice;

  bool get usesConfigurableThermalWidth => this == InvoiceTemplate.arabicThermal;

  bool get isCustomerFacing => this != InvoiceTemplate.kitchen;
  bool get isSecondaryEligible => !isPaged && !isArabicFirst;

  /// The Arabic thermal template is still valid for a raw network thermal
  /// destination because CounterIQ rasterises the fully-shaped bilingual PDF
  /// and sends the result as ESC/POS image data. Paged templates remain local
  /// Windows/PDF only.
  bool get supportsRawNetwork => !isPaged;

  /// Default thermal paper code. Arabic Thermal may override this with the
  /// branch-configured [PrinterConfig.thermalPaperSize].
  String get paperWidthCode => switch (this) {
        InvoiceTemplate.compact => 'mm58',
        InvoiceTemplate.standardInvoice ||
        InvoiceTemplate.arabicStandardInvoice => 'a4',
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
        InvoiceTemplate.standardInvoice ||
        InvoiceTemplate.arabicThermal ||
        InvoiceTemplate.arabicStandardInvoice => const InvoiceSections(
            header: true,
            customer: true,
            totalsBreakdown: true,
            footer: true,
          ),
      };

  /// Strict template resolver used when reading the server-side template
  /// catalogue. Unknown values must never silently become Standard Receipt,
  /// otherwise one unsupported/mismatched server value creates a duplicate
  /// Standard Receipt option in Printer Settings.
  static InvoiceTemplate? tryFromValue(String? v, {String? label}) {
    String normalize(String? value) => (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-]+'), '_');

    final value = normalize(v);
    final byValue = switch (value) {
      'standard' => InvoiceTemplate.standard,
      'compact' => InvoiceTemplate.compact,
      'kitchen' => InvoiceTemplate.kitchen,
      'standard_invoice' || 'standardinvoice' =>
        InvoiceTemplate.standardInvoice,
      'arabic_thermal' ||
      'arabicthermal' ||
      'arabic_thermal_receipt' ||
      'arabic_receipt' =>
        InvoiceTemplate.arabicThermal,
      'arabic_standard_invoice' ||
      'arabicstandardinvoice' ||
      'arabic_invoice' ||
      'arabic_a4_invoice' =>
        InvoiceTemplate.arabicStandardInvoice,
      _ => null,
    };
    if (byValue != null) return byValue;

    // Older/newer backend builds may expose a different internal value while
    // still returning the stable human-readable catalogue label. Use that as
    // a compatibility fallback instead of incorrectly mapping to Standard.
    final labelValue = normalize(label);
    return switch (labelValue) {
      'standard_receipt' => InvoiceTemplate.standard,
      'compact_receipt' => InvoiceTemplate.compact,
      'kitchen_ticket' => InvoiceTemplate.kitchen,
      'standard_invoice' => InvoiceTemplate.standardInvoice,
      'arabic_thermal_receipt' => InvoiceTemplate.arabicThermal,
      'arabic_standard_invoice' => InvoiceTemplate.arabicStandardInvoice,
      _ => null,
    };
  }

  static InvoiceTemplate fromValue(String? v) {
    return tryFromValue(v) ?? InvoiceTemplate.standard;
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
