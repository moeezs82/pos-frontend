import 'dart:typed_data';

import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class ThermalPrinterService {
  ThermalPrinterService._();
  static final instance = ThermalPrinterService._();

  static const InvoiceSections _defaultSections = InvoiceSections(
    header: true,
    customer: true,
    totalsBreakdown: true,
    footer: true,
  );

  /// Printing to a printer installed on this computer's OS print spooler.
  /// Not wired up yet — callers catch this and fall back to PDF preview.
  Future<void> printSaleReceiptWindows({
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
    InvoiceSections sections = _defaultSections,
    String paperWidth = 'mm80',
    List<String> footerLines = const [],
  }) async {
    throw UnsupportedError(
      'Local/USB printer support is not wired up yet for "$printerName". '
      'Use a network printer in Printer Settings, or print to PDF for now.',
    );
  }

  /// Printing to an ESC/POS thermal printer over the network (WiFi/Ethernet).
  Future<void> printSaleReceiptNetwork({
    required String printerIp,
    int port = 9100,
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
    InvoiceSections sections = _defaultSections,
    String paperWidth = 'mm80',
    List<String> footerLines = const [],
  }) async {
    final profile = await CapabilityProfile.load();
    final paper = paperWidth == 'mm58' ? PaperSize.mm58 : PaperSize.mm80;
    final printer = NetworkPrinter(paper, profile);

    final result = await printer.connect(
      printerIp,
      port: port,
      timeout: const Duration(seconds: 7),
    );

    if (result != PosPrintResult.success) {
      throw Exception('Could not reach printer at $printerIp:$port (${result.msg})');
    }

    try {
      _writeReceipt(
        printer,
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
        cashReceived: cashReceived,
        changeAmount: changeAmount,
        meta: meta,
        sections: sections,
        footerLines: footerLines,
      );
    } finally {
      printer.disconnect();
    }
  }

  /// Sends a short test ticket to confirm the printer is reachable.
  Future<void> testPrintNetwork({
    required String printerIp,
    int port = 9100,
    String shopName = 'Test Print',
    String paperWidth = 'mm80',
  }) async {
    final profile = await CapabilityProfile.load();
    final paper = paperWidth == 'mm58' ? PaperSize.mm58 : PaperSize.mm80;
    final printer = NetworkPrinter(paper, profile);

    final result = await printer.connect(
      printerIp,
      port: port,
      timeout: const Duration(seconds: 7),
    );

    if (result != PosPrintResult.success) {
      throw Exception('Could not reach printer at $printerIp:$port (${result.msg})');
    }

    try {
      printer.text(
        shopName,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
      );
      printer.text('Test print', styles: const PosStyles(align: PosAlign.center));
      printer.text(DateTime.now().toString(), styles: const PosStyles(align: PosAlign.center));
      printer.hr();
      printer.text('If you can read this, the printer\nis connected and working.');
      printer.feed(2);
      printer.cut();
    } finally {
      printer.disconnect();
    }
  }

  void _writeReceipt(
    NetworkPrinter printer, {
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
    List<String> footerLines = const [],
  }) {
    final snapRaw = meta?['customer_snapshot'];
    final snap = (snapRaw is Map) ? snapRaw.cast<String, dynamic>() : <String, dynamic>{};
    final cName = (snap['name'] ?? '').toString().trim();
    final cPhone = (snap['phone'] ?? '').toString().trim();

    final delivery = (meta?['delivery'] is num)
        ? (meta!['delivery'] as num).toDouble()
        : double.tryParse((meta?['delivery'] ?? '').toString()) ?? 0.0;

    if (sections.header) {
      printer.text(shopName, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      if (shopAddress != null && shopAddress.trim().isNotEmpty) {
        printer.text(shopAddress, styles: const PosStyles(align: PosAlign.center));
      }
      if (shopPhone != null && shopPhone.trim().isNotEmpty) {
        printer.text(shopPhone, styles: const PosStyles(align: PosAlign.center));
      }
      printer.hr();
    } else {
      printer.text(shopName, styles: const PosStyles(align: PosAlign.center, bold: true));
    }

    printer.text('Receipt# $receiptNo', styles: const PosStyles(align: PosAlign.center, bold: true));
    // Show a subtle note for offline receipts (pending server sync).
    if (receiptNo.startsWith('OFF-')) {
      printer.text('Offline Receipt - Pending Sync', styles: const PosStyles(align: PosAlign.center));
    }
    printer.text(_fmtDate(dateTime), styles: const PosStyles(align: PosAlign.center));
    printer.hr();

    if (sections.customer && (cName.isNotEmpty || cPhone.isNotEmpty)) {
      if (cName.isNotEmpty) printer.text('Customer: $cName');
      if (cPhone.isNotEmpty) printer.text('Phone: $cPhone');
      printer.hr();
    }

    if (sections.totalsBreakdown) {
      printer.row([
        PosColumn(text: 'Item', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
        PosColumn(text: 'Total', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
    } else {
      printer.row([
        PosColumn(text: 'Item', width: 9, styles: const PosStyles(bold: true)),
        PosColumn(text: 'Qty', width: 3, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
    }

    for (final it in items) {
      if (sections.totalsBreakdown) {
        printer.row([
          PosColumn(text: it.name, width: 6),
          PosColumn(text: _q(it.qty), width: 2, styles: const PosStyles(align: PosAlign.right)),
          PosColumn(text: _m(it.total), width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]);
      } else {
        printer.row([
          PosColumn(text: it.name, width: 9),
          PosColumn(text: _q(it.qty), width: 3, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
    }
    printer.hr();

    if (sections.totalsBreakdown) {
      printer.row([
        PosColumn(text: 'Subtotal', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: _m(subtotal), width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
      if (discount > 0) {
        printer.row([
          PosColumn(text: 'Discount', width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text: '-${_m(discount)}', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]);
      }
      if (tax > 0) {
        printer.row([
          PosColumn(text: 'Tax', width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text: _m(tax), width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]);
      }
      if (delivery > 0) {
        printer.row([
          PosColumn(text: 'Delivery', width: 8, styles: const PosStyles(bold: true)),
          PosColumn(text: _m(delivery), width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
        ]);
      }
      printer.hr();
    }

    printer.row([
      PosColumn(text: 'Grand Total', width: 8, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(text: _m(grandTotal), width: 4, styles: const PosStyles(bold: true, height: PosTextSize.size2, align: PosAlign.right)),
    ]);
    if (cashReceived > 0) {
      printer.row([
        PosColumn(text: 'Cash Received', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: _m(cashReceived), width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
    }
    if (changeAmount > 0) {
      printer.row([
        PosColumn(text: 'Change', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: _m(changeAmount), width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
    }
    printer.hr();

    if (sections.footer) {
      final lines = footerLines.where((l) => l.trim().isNotEmpty).toList();
      for (final line in lines) {
        printer.text(line, styles: const PosStyles(align: PosAlign.center, bold: true));
      }
      if (lines.isNotEmpty) printer.feed(1);
    }

    printer.feed(2);
    printer.cut();
  }

  static String _fmtDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} "
      "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  static String _m(num v) => v.toStringAsFixed(2);
  static String _q(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toString();
}

class SaleReceiptItem {
  final String name;
  final double price;
  final double qty;
  final double total;

  SaleReceiptItem({
    required this.name,
    required this.price,
    required this.qty,
    required this.total,
  });
}
