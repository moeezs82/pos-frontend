/// The predefined invoice/receipt layouts a printer destination can use.
/// Mirrors the backend's `App\Enums\InvoiceTemplate` exactly — same values,
/// same section defaults — so picking "Kitchen" here means the same thing
/// it means when the backend reports it back.
///
/// Both the PDF preview (ReceiptPreviewService) and the real ESC/POS print
/// (ThermalPrinterService) render from this same section list, so what you
/// see in the preview screen is what actually prints.
enum InvoiceTemplate {
  standard,
  compact,
  kitchen;

  String get value => switch (this) {
        InvoiceTemplate.standard => 'standard',
        InvoiceTemplate.compact => 'compact',
        InvoiceTemplate.kitchen => 'kitchen',
      };

  String get label => switch (this) {
        InvoiceTemplate.standard => 'Standard Receipt',
        InvoiceTemplate.compact => 'Compact Receipt',
        InvoiceTemplate.kitchen => 'Kitchen Ticket',
      };

  String get description => switch (this) {
        InvoiceTemplate.standard =>
          'Full customer receipt: shop details, customer info, itemised totals, and a footer.',
        InvoiceTemplate.compact =>
          'Narrow 58mm layout for small printers: shop name and items only, no customer details.',
        InvoiceTemplate.kitchen =>
          'Item list for the kitchen: who it is for and what to make, no prices, no shop header.',
      };

  /// 'mm58' | 'mm80'
  String get paperWidthCode => this == InvoiceTemplate.compact ? 'mm58' : 'mm80';

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
            totalsBreakdown: false,
            footer: false,
          ),
      };

  static InvoiceTemplate fromValue(String? v) {
    return InvoiceTemplate.values.firstWhere(
      (t) => t.value == v,
      orElse: () => InvoiceTemplate.standard,
    );
  }
}

/// Which sections of the receipt actually render. Four toggles (logo removed
/// per product spec — no logo on any print): header (shop name/address/
/// phone), customer info, the totals breakdown (subtotal/discount/tax/
/// delivery — grand total always shows regardless), and the footer.
class InvoiceSections {
  final bool header;
  final bool customer;
  final bool totalsBreakdown;
  final bool footer;

  const InvoiceSections({
    required this.header,
    required this.customer,
    required this.totalsBreakdown,
    required this.footer,
  });

  factory InvoiceSections.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) => json[key] is bool ? json[key] as bool : fallback;
    final fallback = InvoiceTemplate.standard.sections;
    return InvoiceSections(
      header: flag('header', fallback.header),
      customer: flag('customer', fallback.customer),
      totalsBreakdown: flag('totals_breakdown', fallback.totalsBreakdown),
      footer: flag('footer', fallback.footer),
    );
  }
}
