import 'dart:typed_data';

import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/models/item_discount_display.dart';
import 'package:enterprise_pos/models/receipt_footer_style.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Direct printing through printers installed in the operating system.
///
/// On Windows this uses the configured Windows printer queue/driver, so USB,
/// Wi-Fi, LAN and Bluetooth printers that appear in Windows Printers & scanners
/// can be selected and printed to without showing the system print dialog.
class LocalPrinterService {
  LocalPrinterService._();
  static final instance = LocalPrinterService._();

  Future<List<Printer>> listInstalledPrinters() => Printing.listPrinters();

  Future<Printer> requirePrinter(String printerName) async {
    final sw = Stopwatch()..start();
    print('[LOCAL-PRINT-TIMING] requirePrinter start printer=$printerName');
    final wanted = printerName.trim();
    if (wanted.isEmpty) {
      throw Exception('Select an installed printer first.');
    }

    final printers = await Printing.listPrinters();
    print(
      '[LOCAL-PRINT-TIMING] Printing.listPrinters completed in ${sw.elapsedMilliseconds}ms count=${printers.length}',
    );
    final wantedLower = wanted.toLowerCase();
    for (final printer in printers) {
      if (printer.name.trim().toLowerCase() == wantedLower) {
        return printer;
      }
    }

    throw Exception(
      'The configured printer "$wanted" is not available on this computer. '
      'Open Printer Settings and refresh the installed printer list.',
    );
  }

  Future<Uint8List> printSaleReceipt({
    required String printerName,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    required String receiptNo,
    required DateTime dateTime,
    required List<SaleReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    required double cashReceived,
    required double changeAmount,
    Map<String, dynamic>? meta,
    required InvoiceSections sections,
    String paperWidth = 'mm80',
    List<String> footerLines = const [],
    List<ReceiptFooterStyle> footerLineStyles = const [],
    String? receiptHeader,
    String invoiceHeading = 'SALES INVOICE',
    bool showLogo = false,
    String? logoData,
    bool showQr = false,
    String? qrUrl,
    String qrCaption = 'Scan to review us',
    InvoiceTemplate? template,
    String? jobName,
  }) async {
    final totalTiming = Stopwatch()..start();
    print('[LOCAL-PRINT-TIMING] printSaleReceipt start receipt=$receiptNo');
    final printer = await requirePrinter(printerName);
    print(
      '[LOCAL-PRINT-TIMING] printer resolved +${totalTiming.elapsedMilliseconds}ms name=${printer.name}',
    );
    final effectiveMeta = <String, dynamic>{
      ...?meta,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
    };

    final pdfTiming = Stopwatch()..start();
    final bytes = await ReceiptPreviewService.instance.buildReceiptPdf(
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      receiptNo: receiptNo,
      dateTime: dateTime,
      items: items,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      grandTotal: grandTotal,
      meta: effectiveMeta,
      sections: sections,
      paperWidth: paperWidth,
      footerLines: footerLines,
      footerLineStyles: footerLineStyles,
      receiptHeader: receiptHeader,
      invoiceHeading: invoiceHeading,
      showLogo: showLogo,
      logoData: logoData,
      showQr: showQr,
      qrUrl: qrUrl,
      qrCaption: qrCaption,
      template: template,
    );
    print(
      '[LOCAL-PRINT-TIMING] PDF built in ${pdfTiming.elapsedMilliseconds}ms bytes=${bytes.length}',
    );

    final format = _pageFormat(paperWidth);
    final directPrintTiming = Stopwatch()..start();
    print('[LOCAL-PRINT-TIMING] Printing.directPrintPdf starting');
    final printed = await Printing.directPrintPdf(
      printer: printer,
      name: jobName ?? 'Receipt $receiptNo',
      format: format,
      dynamicLayout: false,
      // On Windows, let the selected queue use the printable origin and paper
      // configuration already defined by its installed driver. This is
      // especially important for USB thermal printers whose printable area is
      // narrower/offset from the nominal 58 mm or 80 mm roll.
      usePrinterSettings: paperWidth == 'mm58' || paperWidth == 'mm80',
      onLayout: (_) async => bytes,
    );
    print(
      '[LOCAL-PRINT-TIMING] Printing.directPrintPdf completed in ${directPrintTiming.elapsedMilliseconds}ms printed=$printed total=${totalTiming.elapsedMilliseconds}ms',
    );

    if (!printed) {
      throw Exception('Windows did not accept the print job for "${printer.name}".');
    }
    return bytes;
  }

  Future<void> testReceipt({
    required String printerName,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    required InvoiceSections sections,
    String paperWidth = 'mm80',
    List<String> footerLines = const [],
    List<ReceiptFooterStyle> footerLineStyles = const [],
    String? receiptHeader,
    String copyLabel = 'LOCAL PRINTER TEST',
    String invoiceHeading = 'SALES INVOICE',
    bool showLogo = false,
    String? logoData,
    bool showQr = false,
    String? qrUrl,
    String qrCaption = 'Scan to review us',
    InvoiceTemplate? template,
    ItemDiscountDisplay itemDiscountDisplay = ItemDiscountDisplay.compact,
  }) async {
    final now = DateTime.now();
    await printSaleReceipt(
      printerName: printerName,
      shopName: shopName.trim().isEmpty ? 'CounterIQ' : shopName.trim(),
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      receiptNo: "TEST-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}",
      dateTime: now,
      items: [
        SaleReceiptItem(
          name: copyLabel,
          secondaryName: template?.isArabicFirst == true ? 'اختبار طباعة' : null,
          price: 1250,
          qty: 1,
          total: 1200,
          unitName: 'PCS',
          discountAmount: 50,
        ),
      ],
      subtotal: 1250,
      discount: 50,
      tax: 0,
      grandTotal: 1200,
      cashReceived: 0,
      changeAmount: 0,
      meta: <String, dynamic>{
        'customer_snapshot': {'name': 'Walk-in Customer'},
        'payments_snapshot': [
          {'method': 'cash', 'label': 'Cash', 'amount': 1200},
        ],
        'item_discount_display': itemDiscountDisplay.value,
      },
      sections: sections,
      paperWidth: paperWidth,
      footerLines: [
        ...footerLines,
        'Printer connection successful',
      ],
      footerLineStyles: [
        ...footerLineStyles,
        const ReceiptFooterStyle(),
      ],
      receiptHeader: receiptHeader,
      invoiceHeading: invoiceHeading,
      showLogo: showLogo,
      logoData: logoData,
      showQr: showQr,
      qrUrl: qrUrl,
      qrCaption: qrCaption,
      template: template,
      jobName: 'CounterIQ Printer Test',
    );
  }

  PdfPageFormat _pageFormat(String paperWidth) =>
      ReceiptPreviewService.instance.pageFormatForPaperWidth(paperWidth);
}
