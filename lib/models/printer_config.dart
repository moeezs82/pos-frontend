import 'invoice_template.dart';

class PrinterConfig {
  final int? branchId;
  final String? branchName;
  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;

  /// Footer lines printed at the bottom of every receipt.
  /// Each entry becomes a separate centred line on the ticket.
  final List<String> footerLines;

  /// 'network' | 'local' | 'none'
  final String activeConnection;

  final String? networkIp;
  final int networkPort;
  final String? localPrinterName;
  final InvoiceTemplate mainInvoiceTemplate;

  final bool kitchenPrintEnabled;
  final String? kitchenNetworkIp;
  final int kitchenNetworkPort;
  final String? kitchenLocalPrinterName;
  final InvoiceTemplate kitchenInvoiceTemplate;

  // Legacy fields kept so older call sites that read mainPrinterName/
  // kitchenPrinterName keep working unchanged.
  final String? mainPrinterName;
  final String? kitchenPrinterName;

  const PrinterConfig({
    this.branchId,
    this.branchName,
    this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.footerLines = const [],
    this.activeConnection = 'none',
    this.networkIp,
    this.networkPort = 9100,
    this.localPrinterName,
    this.mainInvoiceTemplate = InvoiceTemplate.standard,
    this.kitchenPrintEnabled = false,
    this.kitchenNetworkIp,
    this.kitchenNetworkPort = 9100,
    this.kitchenLocalPrinterName,
    this.kitchenInvoiceTemplate = InvoiceTemplate.kitchen,
    this.mainPrinterName,
    this.kitchenPrinterName,
  });

  bool get isConfigured => activeConnection != 'none';

  static List<String> _parseFooterLines(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    // Stored as newline-delimited string (older schema)
    final str = raw.toString().trim();
    if (str.isEmpty) return [];
    return str.split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    int toPort(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? fallback;
    }

    return PrinterConfig(
      branchId: json['branch_id'] is int ? json['branch_id'] as int : int.tryParse((json['branch_id'] ?? '').toString()),
      branchName: json['branch_name']?.toString(),
      shopName: json['shop_name']?.toString(),
      shopAddress: json['shop_address']?.toString(),
      shopPhone: json['shop_phone']?.toString(),
      footerLines: _parseFooterLines(json['footer_lines']),
      activeConnection: (json['active_connection'] ?? 'none').toString(),
      networkIp: json['network_ip']?.toString(),
      networkPort: toPort(json['network_port'], 9100),
      localPrinterName: json['local_printer_name']?.toString(),
      mainInvoiceTemplate: InvoiceTemplate.fromValue(json['main_invoice_template']?.toString()),
      kitchenPrintEnabled: json['kitchen_print_enabled'] == true,
      kitchenNetworkIp: json['kitchen_network_ip']?.toString(),
      kitchenNetworkPort: toPort(json['kitchen_network_port'], 9100),
      kitchenLocalPrinterName: json['kitchen_local_printer_name']?.toString(),
      kitchenInvoiceTemplate: InvoiceTemplate.fromValue(json['kitchen_invoice_template']?.toString() ?? InvoiceTemplate.kitchen.value),
      mainPrinterName: json['main_printer_name']?.toString(),
      kitchenPrinterName: json['kitchen_printer_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'branch_id': branchId,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_phone': shopPhone,
      'footer_lines': footerLines,
      'active_connection': activeConnection,
      'network_ip': networkIp,
      'network_port': networkPort,
      'local_printer_name': localPrinterName,
      'main_invoice_template': mainInvoiceTemplate.value,
      'kitchen_print_enabled': kitchenPrintEnabled,
      'kitchen_network_ip': kitchenNetworkIp,
      'kitchen_network_port': kitchenNetworkPort,
      'kitchen_local_printer_name': kitchenLocalPrinterName,
      'kitchen_invoice_template': kitchenInvoiceTemplate.value,
    };
  }

  PrinterConfig copyWith({
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    List<String>? footerLines,
    String? activeConnection,
    String? networkIp,
    int? networkPort,
    String? localPrinterName,
    InvoiceTemplate? mainInvoiceTemplate,
    bool? kitchenPrintEnabled,
    String? kitchenNetworkIp,
    int? kitchenNetworkPort,
    String? kitchenLocalPrinterName,
    InvoiceTemplate? kitchenInvoiceTemplate,
  }) {
    return PrinterConfig(
      branchId: branchId,
      branchName: branchName,
      shopName: shopName ?? this.shopName,
      shopAddress: shopAddress ?? this.shopAddress,
      shopPhone: shopPhone ?? this.shopPhone,
      footerLines: footerLines ?? this.footerLines,
      activeConnection: activeConnection ?? this.activeConnection,
      networkIp: networkIp ?? this.networkIp,
      networkPort: networkPort ?? this.networkPort,
      localPrinterName: localPrinterName ?? this.localPrinterName,
      mainInvoiceTemplate: mainInvoiceTemplate ?? this.mainInvoiceTemplate,
      kitchenPrintEnabled: kitchenPrintEnabled ?? this.kitchenPrintEnabled,
      kitchenNetworkIp: kitchenNetworkIp ?? this.kitchenNetworkIp,
      kitchenNetworkPort: kitchenNetworkPort ?? this.kitchenNetworkPort,
      kitchenLocalPrinterName: kitchenLocalPrinterName ?? this.kitchenLocalPrinterName,
      kitchenInvoiceTemplate: kitchenInvoiceTemplate ?? this.kitchenInvoiceTemplate,
    );
  }
}
