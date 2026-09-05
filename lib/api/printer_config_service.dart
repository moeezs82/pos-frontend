import 'package:enterprise_pos/api/core/api_client.dart';

import '../models/invoice_template.dart';
import '../models/item_discount_display.dart';
import '../models/printer_config.dart';
import '../models/receipt_footer_style.dart';
import '../models/whatsapp_invoice_format.dart';

class PrinterConfigService {
  final ApiClient _client;

  PrinterConfigService({required String token}) : _client = ApiClient(token: token);

  Future<PrinterConfig> getPrinterConfig() async {
    final res = await _client.post("/printer-config");
    if (res["success"] == true) {
      return PrinterConfig.fromJson(res["data"] ?? {});
    }
    throw Exception(res["message"] ?? "Failed to fetch printer config");
  }

  Future<List<PrinterConfig>> getAllPrinterSettings() async {
    final res = await _client.get("/printer-config/all");
    if (res["success"] == true) {
      final rows = (res["data"]?["settings"] as List? ?? []);
      return rows
          .whereType<Map>()
          .map((e) => PrinterConfig.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    throw Exception(res["message"] ?? "Failed to fetch printer settings");
  }

  Future<List<InvoiceTemplate>> getTemplates() async {
    try {
      final res = await _client.get("/printer-config/templates");
      if (res["success"] == true) {
        final rows = (res["data"]?["templates"] as List? ?? []);
        final templates = <InvoiceTemplate>[];

        for (final row in rows.whereType<Map>()) {
          final template = InvoiceTemplate.tryFromValue(
            row['value']?.toString(),
            label: row['label']?.toString(),
          );

          // Never turn an unknown backend template into Standard Receipt.
          // Also de-duplicate aliases if a mixed-version backend happens to
          // publish the same logical template more than once.
          if (template != null && !templates.contains(template)) {
            templates.add(template);
          }
        }

        if (templates.isNotEmpty) return templates;
      }
    } catch (_) {}

    // The template catalogue is static in the Flutter application, so a
    // temporary catalogue request failure can safely fall back to the local
    // supported set.
    return InvoiceTemplate.values;
  }

  Future<PrinterConfig> savePrinterConfig({
    required int branchId,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    List<String> footerLines = const [],
    List<ReceiptFooterStyle> footerLineStyles = const [],
    required String activeConnection,
    String? networkIp,
    int networkPort = 9100,
    String? localPrinterName,
    InvoiceTemplate mainInvoiceTemplate = InvoiceTemplate.standard,
    String invoicePaperSize = 'a4',
    String thermalPaperSize = 'mm80',
    String invoiceHeading = 'SALES INVOICE',
    bool printLogoEnabled = false,
    String? printLogoData,
    bool qrCodeEnabled = false,
    String? qrCodeUrl,
    String qrCodeCaption = 'Scan to review us',
    WhatsAppInvoiceFormat whatsappInvoiceFormat = WhatsAppInvoiceFormat.pdf,
    InvoiceTemplate whatsappInvoiceTemplate = InvoiceTemplate.standard,
    String whatsappMessageTemplate = '',
    ItemDiscountDisplay itemDiscountDisplay = ItemDiscountDisplay.compact,
    bool whatsappShowCustomerBalance = false,
    bool secondaryPrintEnabled = false,
    String? secondaryNetworkIp,
    int secondaryNetworkPort = 9100,
    String? secondaryLocalPrinterName,
    InvoiceTemplate secondaryInvoiceTemplate = InvoiceTemplate.kitchen,
    String secondaryReceiptHeader = 'KITCHEN COPY',
    bool barcodePrintEnabled = false,
    String barcodeConnection = 'dialog',
    String? barcodeLocalPrinterName,
    String? barcodeNetworkIp,
    int barcodeNetworkPort = 9100,
    String barcodePrinterLanguage = 'driver',
    double barcodeLabelWidthMm = 50,
    double barcodeLabelHeightMm = 30,
    double barcodeLabelGapMm = 2,
    int barcodeDpi = 203,
    String barcodeOrientation = 'portrait',
    String barcodeCurrency = 'KD',
    bool barcodeShowName = true,
    bool barcodeShowValue = true,
    bool barcodeShowPrice = true,
    bool barcodeShowVariantDetails = true,
    bool devCreditEnabled = true,
    String devCreditText = 'Powered by A Developers',
  }) async {
    final res = await _client.post("/printer-config/save", body: {
      'branch_id': branchId,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_phone': shopPhone,
      'footer_lines': footerLines,
      'footer_line_styles': footerLineStyles.map((style) => style.toJson()).toList(),
      'active_connection': activeConnection,
      'network_ip': networkIp,
      'network_port': networkPort,
      'local_printer_name': localPrinterName,
      'main_invoice_template': mainInvoiceTemplate.value,
      'invoice_paper_size': invoicePaperSize,
      'thermal_paper_size': thermalPaperSize,
      'invoice_heading': invoiceHeading,
      'print_logo_enabled': printLogoEnabled,
      'print_logo_data': printLogoData,
      'qr_code_enabled': qrCodeEnabled,
      'qr_code_url': qrCodeUrl,
      'qr_code_caption': qrCodeCaption,
      'whatsapp_invoice_format': whatsappInvoiceFormat.value,
      'whatsapp_invoice_template': whatsappInvoiceTemplate.value,
      'whatsapp_message_template': whatsappMessageTemplate,
      'item_discount_display': itemDiscountDisplay.value,
      'whatsapp_show_customer_balance': whatsappShowCustomerBalance,
      'secondary_print_enabled': secondaryPrintEnabled,
      'secondary_network_ip': secondaryNetworkIp,
      'secondary_network_port': secondaryNetworkPort,
      'secondary_local_printer_name': secondaryLocalPrinterName,
      'secondary_invoice_template': secondaryInvoiceTemplate.value,
      'secondary_receipt_header': secondaryReceiptHeader,
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
      'dev_credit_enabled': devCreditEnabled,
      'dev_credit_text': devCreditText,
    });

    if (res["success"] == true) {
      return PrinterConfig.fromJson(res["data"] ?? {});
    }
    throw Exception(res["message"] ?? "Failed to save printer settings");
  }

  Future<void> validateTestDestination({
    required String activeConnection,
    String? networkIp,
    int networkPort = 9100,
    String? localPrinterName,
  }) async {
    final res = await _client.post("/printer-config/test", body: {
      'active_connection': activeConnection,
      'network_ip': networkIp,
      'network_port': networkPort,
      'local_printer_name': localPrinterName,
    });
    if (res["success"] != true) {
      throw Exception(res["message"] ?? "Destination looks invalid");
    }
  }
}
