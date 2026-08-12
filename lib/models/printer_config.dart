import 'invoice_template.dart';

class PrinterConfig {
  final int? branchId;
  final String? branchName;
  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;
  final List<String> footerLines;

  /// Main receipt/invoice printer: 'network' | 'local' | 'none'.
  final String activeConnection;
  final String? networkIp;
  final int networkPort;
  final String? localPrinterName;
  final InvoiceTemplate mainInvoiceTemplate;

  /// Settings used only by the paged Standard Invoice template.
  final String invoicePaperSize; // a4 | a5 | letter
  final String invoiceHeading;

  /// Shared customer-facing print branding.
  final bool printLogoEnabled;
  final String? printLogoData; // data:image/png|jpeg;base64,...
  final bool qrCodeEnabled;
  final String? qrCodeUrl;
  final String qrCodeCaption;

  /// Optional second receipt destination. The backend still accepts and emits
  /// kitchen_* aliases so older application builds remain compatible.
  final bool secondaryPrintEnabled;
  final String? secondaryNetworkIp;
  final int secondaryNetworkPort;
  final String? secondaryLocalPrinterName;
  final InvoiceTemplate secondaryInvoiceTemplate;
  final String secondaryReceiptHeader;

  /// Barcode label printer configuration.
  final bool barcodeAddonActive;
  final bool barcodePermissionGranted;
  final bool barcodeAccessGranted;
  final bool barcodePrintEnabled;
  final String barcodeConnection;
  final String? barcodeLocalPrinterName;
  final String? barcodeNetworkIp;
  final int barcodeNetworkPort;
  final String barcodePrinterLanguage;
  final double barcodeLabelWidthMm;
  final double barcodeLabelHeightMm;
  final double barcodeLabelGapMm;
  final int barcodeDpi;
  final String barcodeOrientation;
  final String barcodeCurrency;
  final bool barcodeShowName;
  final bool barcodeShowValue;
  final bool barcodeShowPrice;
  final bool barcodeShowVariantDetails;

  // Legacy display helpers retained for older call sites.
  final String? mainPrinterName;
  final String? secondaryPrinterName;

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
    this.invoicePaperSize = 'a4',
    this.invoiceHeading = 'SALES INVOICE',
    this.printLogoEnabled = false,
    this.printLogoData,
    this.qrCodeEnabled = false,
    this.qrCodeUrl,
    this.qrCodeCaption = 'Scan to review us',
    this.secondaryPrintEnabled = false,
    this.secondaryNetworkIp,
    this.secondaryNetworkPort = 9100,
    this.secondaryLocalPrinterName,
    this.secondaryInvoiceTemplate = InvoiceTemplate.kitchen,
    this.secondaryReceiptHeader = 'KITCHEN COPY',
    this.barcodeAddonActive = false,
    this.barcodePermissionGranted = false,
    this.barcodeAccessGranted = false,
    this.barcodePrintEnabled = false,
    this.barcodeConnection = 'dialog',
    this.barcodeLocalPrinterName,
    this.barcodeNetworkIp,
    this.barcodeNetworkPort = 9100,
    this.barcodePrinterLanguage = 'driver',
    this.barcodeLabelWidthMm = 50,
    this.barcodeLabelHeightMm = 30,
    this.barcodeLabelGapMm = 2,
    this.barcodeDpi = 203,
    this.barcodeOrientation = 'portrait',
    this.barcodeCurrency = 'KD',
    this.barcodeShowName = true,
    this.barcodeShowValue = true,
    this.barcodeShowPrice = true,
    this.barcodeShowVariantDetails = true,
    this.mainPrinterName,
    this.secondaryPrinterName,
  });

  bool get isConfigured => activeConnection != 'none';
  bool get isBarcodeConfigured => barcodeAccessGranted && barcodePrintEnabled;
  bool get isPagedInvoice => mainInvoiceTemplate.isPaged;
  String get mainPaperCode =>
      mainInvoiceTemplate.isPaged ? invoicePaperSize : mainInvoiceTemplate.paperWidthCode;

  // Source compatibility for receipt-printing code during rolling upgrades.
  bool get kitchenPrintEnabled => secondaryPrintEnabled;
  String? get kitchenNetworkIp => secondaryNetworkIp;
  int get kitchenNetworkPort => secondaryNetworkPort;
  String? get kitchenLocalPrinterName => secondaryLocalPrinterName;
  InvoiceTemplate get kitchenInvoiceTemplate => secondaryInvoiceTemplate;
  String? get kitchenPrinterName => secondaryPrinterName;

  static List<String> _parseFooterLines(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    final str = raw.toString().trim();
    if (str.isEmpty) return [];
    return str.split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'on'}.contains(value.toString().toLowerCase());
  }

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value, int fallback) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString()) ?? fallback;
    }

    double toDouble(dynamic value, double fallback) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString()) ?? fallback;
    }

    dynamic preferred(String current, String legacy) =>
        json.containsKey(current) ? json[current] : json[legacy];

    return PrinterConfig(
      branchId: json['branch_id'] is int
          ? json['branch_id'] as int
          : int.tryParse((json['branch_id'] ?? '').toString()),
      branchName: json['branch_name']?.toString(),
      shopName: json['shop_name']?.toString(),
      shopAddress: json['shop_address']?.toString(),
      shopPhone: json['shop_phone']?.toString(),
      footerLines: _parseFooterLines(json['footer_lines']),
      activeConnection: (json['active_connection'] ?? 'none').toString(),
      networkIp: json['network_ip']?.toString(),
      networkPort: toInt(json['network_port'], 9100),
      localPrinterName: json['local_printer_name']?.toString(),
      mainInvoiceTemplate:
          InvoiceTemplate.fromValue(json['main_invoice_template']?.toString()),
      invoicePaperSize: (json['invoice_paper_size'] ?? 'a4').toString(),
      invoiceHeading: (json['invoice_heading'] ?? 'SALES INVOICE').toString(),
      printLogoEnabled: _bool(json['print_logo_enabled']),
      printLogoData: json['print_logo_data']?.toString(),
      qrCodeEnabled: _bool(json['qr_code_enabled']),
      qrCodeUrl: json['qr_code_url']?.toString(),
      qrCodeCaption: (json['qr_code_caption'] ?? 'Scan to review us').toString(),
      secondaryPrintEnabled:
          _bool(preferred('secondary_print_enabled', 'kitchen_print_enabled')),
      secondaryNetworkIp:
          preferred('secondary_network_ip', 'kitchen_network_ip')?.toString(),
      secondaryNetworkPort:
          toInt(preferred('secondary_network_port', 'kitchen_network_port'), 9100),
      secondaryLocalPrinterName:
          preferred('secondary_local_printer_name', 'kitchen_local_printer_name')?.toString(),
      secondaryInvoiceTemplate: InvoiceTemplate.fromValue(
        preferred('secondary_invoice_template', 'kitchen_invoice_template')?.toString() ??
            InvoiceTemplate.kitchen.value,
      ),
      secondaryReceiptHeader:
          (json['secondary_receipt_header'] ?? 'KITCHEN COPY').toString(),
      barcodeAddonActive: _bool(json['barcode_addon_active']),
      barcodePermissionGranted: _bool(json['barcode_permission_granted']),
      barcodeAccessGranted: _bool(json['barcode_access_granted']),
      barcodePrintEnabled: _bool(json['barcode_print_enabled']),
      barcodeConnection: (json['barcode_connection'] ?? 'dialog').toString(),
      barcodeLocalPrinterName: json['barcode_local_printer_name']?.toString(),
      barcodeNetworkIp: json['barcode_network_ip']?.toString(),
      barcodeNetworkPort: toInt(json['barcode_network_port'], 9100),
      barcodePrinterLanguage:
          (json['barcode_printer_language'] ?? 'driver').toString(),
      barcodeLabelWidthMm: toDouble(json['barcode_label_width_mm'], 50),
      barcodeLabelHeightMm: toDouble(json['barcode_label_height_mm'], 30),
      barcodeLabelGapMm: toDouble(json['barcode_label_gap_mm'], 2),
      barcodeDpi: toInt(json['barcode_dpi'], 203),
      barcodeOrientation: (json['barcode_orientation'] ?? 'portrait').toString(),
      barcodeCurrency: (json['barcode_currency'] ?? 'KD').toString(),
      barcodeShowName: _bool(json['barcode_show_name'], fallback: true),
      barcodeShowValue: _bool(json['barcode_show_value'], fallback: true),
      barcodeShowPrice: _bool(json['barcode_show_price'], fallback: true),
      barcodeShowVariantDetails: _bool(json['barcode_show_variant_details'], fallback: true),
      mainPrinterName: json['main_printer_name']?.toString(),
      secondaryPrinterName:
          preferred('secondary_printer_name', 'kitchen_printer_name')?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'branch_id': branchId,
        'branch_name': branchName,
        'shop_name': shopName,
        'shop_address': shopAddress,
        'shop_phone': shopPhone,
        'footer_lines': footerLines,
        'active_connection': activeConnection,
        'network_ip': networkIp,
        'network_port': networkPort,
        'local_printer_name': localPrinterName,
        'main_invoice_template': mainInvoiceTemplate.value,
        'invoice_paper_size': invoicePaperSize,
        'invoice_heading': invoiceHeading,
        'print_logo_enabled': printLogoEnabled,
        'print_logo_data': printLogoData,
        'qr_code_enabled': qrCodeEnabled,
        'qr_code_url': qrCodeUrl,
        'qr_code_caption': qrCodeCaption,
        'secondary_print_enabled': secondaryPrintEnabled,
        'secondary_network_ip': secondaryNetworkIp,
        'secondary_network_port': secondaryNetworkPort,
        'secondary_local_printer_name': secondaryLocalPrinterName,
        'secondary_invoice_template': secondaryInvoiceTemplate.value,
        'secondary_receipt_header': secondaryReceiptHeader,
        'barcode_addon_active': barcodeAddonActive,
        'barcode_permission_granted': barcodePermissionGranted,
        'barcode_access_granted': barcodeAccessGranted,
        'barcode_print_enabled': barcodePrintEnabled,
        'barcode_connection': barcodeConnection,
        'barcode_local_printer_name': barcodeLocalPrinterName,
        'barcode_network_ip': barcodeNetworkIp,
        'barcode_network_port': barcodeNetworkPort,
        'barcode_printer_language': barcodePrinterLanguage,
        'barcode_label_width_mm': barcodeLabelWidthMm,
        'barcode_label_height_mm': barcodeLabelHeightMm,
        'barcode_label_gap_mm': barcodeLabelGapMm,
        'barcode_dpi': barcodeDpi,
        'barcode_orientation': barcodeOrientation,
        'barcode_currency': barcodeCurrency,
        'barcode_show_name': barcodeShowName,
        'barcode_show_value': barcodeShowValue,
        'barcode_show_price': barcodeShowPrice,
        'barcode_show_variant_details': barcodeShowVariantDetails,
        'main_printer_name': mainPrinterName,
        'secondary_printer_name': secondaryPrinterName,
      };

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
    String? invoicePaperSize,
    String? invoiceHeading,
    bool? printLogoEnabled,
    String? printLogoData,
    bool clearPrintLogoData = false,
    bool? qrCodeEnabled,
    String? qrCodeUrl,
    bool clearQrCodeUrl = false,
    String? qrCodeCaption,
    bool? secondaryPrintEnabled,
    String? secondaryNetworkIp,
    int? secondaryNetworkPort,
    String? secondaryLocalPrinterName,
    InvoiceTemplate? secondaryInvoiceTemplate,
    String? secondaryReceiptHeader,
    bool? barcodeAddonActive,
    bool? barcodePermissionGranted,
    bool? barcodeAccessGranted,
    bool? barcodePrintEnabled,
    String? barcodeConnection,
    String? barcodeLocalPrinterName,
    String? barcodeNetworkIp,
    int? barcodeNetworkPort,
    String? barcodePrinterLanguage,
    double? barcodeLabelWidthMm,
    double? barcodeLabelHeightMm,
    double? barcodeLabelGapMm,
    int? barcodeDpi,
    String? barcodeOrientation,
    String? barcodeCurrency,
    bool? barcodeShowName,
    bool? barcodeShowValue,
    bool? barcodeShowPrice,
    bool? barcodeShowVariantDetails,
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
      invoicePaperSize: invoicePaperSize ?? this.invoicePaperSize,
      invoiceHeading: invoiceHeading ?? this.invoiceHeading,
      printLogoEnabled: printLogoEnabled ?? this.printLogoEnabled,
      printLogoData:
          clearPrintLogoData ? null : (printLogoData ?? this.printLogoData),
      qrCodeEnabled: qrCodeEnabled ?? this.qrCodeEnabled,
      qrCodeUrl: clearQrCodeUrl ? null : (qrCodeUrl ?? this.qrCodeUrl),
      qrCodeCaption: qrCodeCaption ?? this.qrCodeCaption,
      secondaryPrintEnabled:
          secondaryPrintEnabled ?? this.secondaryPrintEnabled,
      secondaryNetworkIp: secondaryNetworkIp ?? this.secondaryNetworkIp,
      secondaryNetworkPort:
          secondaryNetworkPort ?? this.secondaryNetworkPort,
      secondaryLocalPrinterName:
          secondaryLocalPrinterName ?? this.secondaryLocalPrinterName,
      secondaryInvoiceTemplate:
          secondaryInvoiceTemplate ?? this.secondaryInvoiceTemplate,
      secondaryReceiptHeader:
          secondaryReceiptHeader ?? this.secondaryReceiptHeader,
      barcodeAddonActive: barcodeAddonActive ?? this.barcodeAddonActive,
      barcodePermissionGranted:
          barcodePermissionGranted ?? this.barcodePermissionGranted,
      barcodeAccessGranted:
          barcodeAccessGranted ?? this.barcodeAccessGranted,
      barcodePrintEnabled: barcodePrintEnabled ?? this.barcodePrintEnabled,
      barcodeConnection: barcodeConnection ?? this.barcodeConnection,
      barcodeLocalPrinterName:
          barcodeLocalPrinterName ?? this.barcodeLocalPrinterName,
      barcodeNetworkIp: barcodeNetworkIp ?? this.barcodeNetworkIp,
      barcodeNetworkPort: barcodeNetworkPort ?? this.barcodeNetworkPort,
      barcodePrinterLanguage:
          barcodePrinterLanguage ?? this.barcodePrinterLanguage,
      barcodeLabelWidthMm:
          barcodeLabelWidthMm ?? this.barcodeLabelWidthMm,
      barcodeLabelHeightMm:
          barcodeLabelHeightMm ?? this.barcodeLabelHeightMm,
      barcodeLabelGapMm: barcodeLabelGapMm ?? this.barcodeLabelGapMm,
      barcodeDpi: barcodeDpi ?? this.barcodeDpi,
      barcodeOrientation: barcodeOrientation ?? this.barcodeOrientation,
      barcodeCurrency: barcodeCurrency ?? this.barcodeCurrency,
      barcodeShowName: barcodeShowName ?? this.barcodeShowName,
      barcodeShowValue: barcodeShowValue ?? this.barcodeShowValue,
      barcodeShowPrice: barcodeShowPrice ?? this.barcodeShowPrice,
      barcodeShowVariantDetails:
          barcodeShowVariantDetails ?? this.barcodeShowVariantDetails,
      mainPrinterName: mainPrinterName,
      secondaryPrinterName: secondaryPrinterName,
    );
  }
}
