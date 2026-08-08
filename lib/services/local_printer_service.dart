import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
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
    final wanted = printerName.trim();
    if (wanted.isEmpty) {
      throw Exception('Select an installed printer first.');
    }

    final printers = await Printing.listPrinters();
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

  Future<void> printSaleReceipt({
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
    String? receiptHeader,
    String? jobName,
  }) async {
    final printer = await requirePrinter(printerName);
    final effectiveMeta = <String, dynamic>{
      ...?meta,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
    };

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
      receiptHeader: receiptHeader,
    );

    final format = _pageFormat(paperWidth);
    final printed = await Printing.directPrintPdf(
      printer: printer,
      name: jobName ?? 'Receipt $receiptNo',
      format: format,
      dynamicLayout: false,
      // On Windows, let the selected queue use the printable origin and paper
      // configuration already defined by its installed driver. This is
      // especially important for USB thermal printers whose printable area is
      // narrower/offset from the nominal 58 mm or 80 mm roll.
      usePrinterSettings: true,
      onLayout: (_) async => bytes,
    );

    if (!printed) {
      throw Exception('Windows did not accept the print job for "${printer.name}".');
    }
  }

  Future<void> testReceipt({
    required String printerName,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    required InvoiceSections sections,
    String paperWidth = 'mm80',
    List<String> footerLines = const [],
    String? receiptHeader,
    String copyLabel = 'LOCAL PRINTER TEST',
  }) {
    final now = DateTime.now();
    return printSaleReceipt(
      printerName: printerName,
      shopName: shopName.trim().isEmpty ? 'CounterIQ' : shopName.trim(),
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      receiptNo: "TEST-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}",
      dateTime: now,
      items: [
        SaleReceiptItem(
          name: copyLabel,
          price: 0,
          qty: 1,
          total: 0,
        ),
      ],
      subtotal: 0,
      discount: 0,
      tax: 0,
      grandTotal: 0,
      cashReceived: 0,
      changeAmount: 0,
      meta: const <String, dynamic>{},
      sections: sections,
      paperWidth: paperWidth,
      footerLines: [
        ...footerLines,
        'Printer connection successful',
      ],
      receiptHeader: receiptHeader,
      jobName: 'CounterIQ Printer Test',
    );
  }

  PdfPageFormat _pageFormat(String paperWidth) =>
      ReceiptPreviewService.instance.pageFormatForPaperWidth(paperWidth);
}
