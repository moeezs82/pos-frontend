import 'dart:convert';

import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/models/item_discount_display.dart';
import 'package:enterprise_pos/models/receipt_footer_style.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:enterprise_pos/utils/customer_phone_utils.dart';
import 'package:enterprise_pos/utils/print_text_utils.dart';
import 'package:enterprise_pos/utils/thermal_receipt_layout.dart';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

class ThermalPrinterService {
  ThermalPrinterService._();
  static final instance = ThermalPrinterService._();

  String _customerDisplayName(Map<String, dynamic> customer) {
    final name = (customer['name'] ?? '').toString().trim();
    final code = (customer['customer_code'] ?? '').toString().trim();
    if (code.isNotEmpty && name.isNotEmpty) return '($code) $name';
    if (name.isNotEmpty) return name;
    if (code.isNotEmpty) return '($code)';
    return '';
  }

  static const InvoiceSections _defaultSections = InvoiceSections(
    header: true,
    customer: true,
    totalsBreakdown: true,
    footer: true,
  );

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
    List<ReceiptFooterStyle> footerLineStyles = const [],
    String? receiptHeader,
    String invoiceHeading = 'SALES INVOICE',
    bool showLogo = false,
    String? logoData,
    bool showQr = false,
    String? qrUrl,
    String qrCaption = 'Scan to review us',
    InvoiceTemplate? template,
    bool devCreditEnabled = false,
    String devCreditText = '',
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

    if (template == InvoiceTemplate.arabicThermal) {
      try {
        await _writeArabicRasterReceipt(
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
          paperWidth: paperWidth,
          footerLines: footerLines,
          footerLineStyles: footerLineStyles,
          showLogo: showLogo,
          logoData: logoData,
          showQr: showQr,
          qrUrl: qrUrl,
          qrCaption: qrCaption,
          devCreditEnabled: devCreditEnabled,
          devCreditText: devCreditText,
        );
      } finally {
        printer.disconnect();
      }
      return;
    }

    try {
      if (showLogo && sections.header) {
        final logo = _decodeLogoImage(logoData, paperWidth == 'mm58' ? 320 : 500);
        if (logo != null) {
          printer.imageRaster(logo, align: PosAlign.center);
          printer.feed(1);
        }
      }
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
        footerLineStyles: footerLineStyles,
        receiptHeader: receiptHeader,
        invoiceHeading: invoiceHeading,
        showQr: showQr,
        qrUrl: qrUrl,
        qrCaption: qrCaption,
        is58mm: paperWidth == 'mm58',
        devCreditEnabled: devCreditEnabled,
        devCreditText: devCreditText,
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
    String? receiptHeader,
    bool showLogo = false,
    String? logoData,
    bool showQr = false,
    String? qrUrl,
    String qrCaption = 'Scan to review us',
    List<String> footerLines = const [],
    List<ReceiptFooterStyle> footerLineStyles = const [],
    InvoiceTemplate? template,
    ItemDiscountDisplay itemDiscountDisplay = ItemDiscountDisplay.compact,
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

    if (template == InvoiceTemplate.arabicThermal) {
      try {
        await _writeArabicRasterReceipt(
          printer,
          shopName: shopName,
          shopAddress: null,
          shopPhone: null,
          receiptNo: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
          dateTime: DateTime.now(),
          items: const [
            SaleReceiptItem(
              name: 'Classic T-Shirt',
              secondaryName: 'تي شيرت كلاسيك',
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
          cashReceived: 1200,
          changeAmount: 0,
          meta: <String, dynamic>{
            'customer_snapshot': {'name': 'Walk-in Customer'},
            'payments_snapshot': [
              {'method': 'cash', 'label': 'Cash', 'amount': 1200},
            ],
            'item_discount_display': itemDiscountDisplay.value,
          },
          paperWidth: paperWidth,
          footerLines: [...footerLines, 'Printer connection successful'],
          footerLineStyles: [
            ...footerLineStyles,
            const ReceiptFooterStyle(),
          ],
          showLogo: showLogo,
          logoData: logoData,
          showQr: showQr,
          qrUrl: qrUrl,
          qrCaption: qrCaption,
        );
      } finally {
        printer.disconnect();
      }
      return;
    }

    try {
      if (showLogo) {
        final logo = _decodeLogoImage(logoData, paperWidth == 'mm58' ? 320 : 500);
        if (logo != null) {
          printer.imageRaster(logo, align: PosAlign.center);
          printer.feed(1);
        }
      }
      final header = (receiptHeader ?? '').trim();
      if (header.isNotEmpty) {
        printer.text(
          header,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        );
      }
      printer.text(
        shopName,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
      );
      printer.text('Test print', styles: const PosStyles(align: PosAlign.center));
      printer.text(DateTime.now().toString(), styles: const PosStyles(align: PosAlign.center));
      printer.hr();
      printer.text('If you can read this, the printer\nis connected and working.');
      if (showQr && _validQrUrl(qrUrl)) {
        printer.feed(1);
        printer.qrcode(
          qrUrl!.trim(),
          size: paperWidth == 'mm58' ? QRSize.size3 : QRSize.size4,
        );
        if (qrCaption.trim().isNotEmpty) {
          printer.text(qrCaption.trim(), styles: const PosStyles(align: PosAlign.center));
        }
      }
      final testFooterLines = [...footerLines, 'Printer connection successful'];
      final testFooterStyles = [
        ...footerLineStyles,
        const ReceiptFooterStyle(),
      ];
      _writeFooterLines(printer, testFooterLines, testFooterStyles);
      printer.feed(2);
      printer.cut();
    } finally {
      printer.disconnect();
    }
  }

  Future<void> _writeArabicRasterReceipt(
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
    required String paperWidth,
    required List<String> footerLines,
    required List<ReceiptFooterStyle> footerLineStyles,
    required bool showLogo,
    String? logoData,
    required bool showQr,
    String? qrUrl,
    required String qrCaption,
    bool devCreditEnabled = false,
    String devCreditText = '',
  }) async {
    final effectiveMeta = <String, dynamic>{
      ...?meta,
      'cash_received': cashReceived,
      'change_amount': changeAmount,
    };

    // Arabic text cannot be safely emitted as a printer-specific code page:
    // shaping/RTL support varies wildly between ESC/POS firmwares. CounterIQ
    // therefore renders the exact bilingual PDF first and rasterises it. The
    // printer only receives pixels, so Arabic output is consistent on common
    // network thermal printers without changing their firmware/code page.
    final pdfBytes = await ReceiptPreviewService.instance.buildReceiptPdf(
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
      sections: InvoiceTemplate.arabicThermal.sections,
      paperWidth: paperWidth,
      footerLines: footerLines,
      footerLineStyles: footerLineStyles,
      showLogo: showLogo,
      logoData: logoData,
      showQr: showQr,
      qrUrl: qrUrl,
      qrCaption: qrCaption,
      template: InvoiceTemplate.arabicThermal,
      devCreditEnabled: devCreditEnabled,
      devCreditText: devCreditText,
    );

    final maxWidth = paperWidth.toLowerCase() == 'mm58' ? 384 : 576;
    await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
      final png = await page.toPng();
      var raster = img.decodePng(png);
      if (raster == null) {
        throw Exception('Could not rasterise Arabic thermal receipt.');
      }
      if (raster.width > maxWidth) {
        raster = img.copyResize(raster, width: maxWidth);
      }

      // Send manageable horizontal slices. Some ESC/POS devices reject one
      // extremely tall bitmap even though they accept the same data in chunks.
      const chunkHeight = 720;
      for (var y = 0; y < raster.height; y += chunkHeight) {
        final height = (raster.height - y) > chunkHeight
            ? chunkHeight
            : raster.height - y;
        final slice = img.copyCrop(
          raster,
          x: 0,
          y: y,
          width: raster.width,
          height: height,
        );
        printer.imageRaster(slice, align: PosAlign.center);
      }
    }

    printer.feed(2);
    printer.cut();
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
    List<ReceiptFooterStyle> footerLineStyles = const [],
    String? receiptHeader,
    String invoiceHeading = 'SALES INVOICE',
    bool showQr = false,
    String? qrUrl,
    String qrCaption = 'Scan to review us',
    bool is58mm = false,
    bool devCreditEnabled = false,
    String devCreditText = '',
  }) {
    final snapRaw = meta?['customer_snapshot'];
    final snap =
        (snapRaw is Map) ? snapRaw.cast<String, dynamic>() : <String, dynamic>{};
    final cName = _customerDisplayName(snap);
    final cPhone = (snap['phone'] ?? '').toString().trim();
    final cAddr = (snap['address'] ?? '').toString().trim();
    final cOtherPhones =
        CustomerPhoneUtils.printableSecondaryPhones(meta, snap);
    final itemDiscountDisplay = itemDiscountDisplayFromValue(
      meta?['item_discount_display']?.toString(),
    );
    final operationalTicket =
        !sections.itemPrices && !sections.totalsBreakdown;
    final showMrp = ThermalReceiptLayout.showsMrp(
      is58mm: is58mm,
      discountDisplay: itemDiscountDisplay,
    );

    final delivery = (meta?['delivery'] is num)
        ? (meta!['delivery'] as num).toDouble()
        : double.tryParse((meta?['delivery'] ?? '').toString()) ?? 0.0;

    // ESC/POS row() divides the paper into 12 units. The item table uses the
    // same column order as the PDF renderer so the two paths stay in step:
    // QTY, RATE, [MRP], AMOUNT, plus a one-unit right gutter that keeps
    // amounts off print heads whose last millimetres print faintly.
    //
    // Unlike the PDF the numbers row is NOT indented under the SL gutter: a
    // 48-column line (32 on 58 mm) has no spare characters once RATE, MRP
    // and AMOUNT each need room for a six-figure amount, and a clipped price
    // is far worse than a missing indent.
    //
    // Every row below must add up to exactly 12.
    const int slUnits = 1;
    const int gutterUnits = 1;
    final int qtyUnits = showMrp ? 2 : 3;
    final int rateUnits = showMrp ? 3 : 4;
    final int mrpUnits = showMrp ? 3 : 0;
    final int amountUnits = showMrp ? 3 : 4;
    final int detailLabelUnits = 12 - amountUnits - gutterUnits;

    const PosStyles boldLeft = PosStyles(bold: true);
    const PosStyles right = PosStyles(align: PosAlign.right);
    const PosStyles rightBold = PosStyles(bold: true, align: PosAlign.right);

    void kv(String label, String value, {bool bold = false}) {
      printer.row([
        PosColumn(text: label, width: 6, styles: PosStyles(bold: bold)),
        PosColumn(
          text: value,
          width: 5,
          styles: PosStyles(bold: bold, align: PosAlign.right),
        ),
        PosColumn(text: '', width: gutterUnits),
      ]);
    }

    void metaRow(String label, String value) {
      printer.row([
        PosColumn(text: label, width: 4),
        PosColumn(text: value, width: 7, styles: rightBold),
        PosColumn(text: '', width: gutterUnits),
      ]);
    }

    // -- HEADER --------------------------------------------------------------
    final secondaryHeader = (receiptHeader ?? '').trim();
    if (secondaryHeader.isNotEmpty) {
      printer.text(
        secondaryHeader,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
    }

    if (sections.header) {
      printer.text(
        shopName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      if (shopAddress != null && shopAddress.trim().isNotEmpty) {
        printer.text(
          shopAddress.trim(),
          styles: const PosStyles(align: PosAlign.center),
        );
      }
      if (shopPhone != null && shopPhone.trim().isNotEmpty) {
        printer.text(
          shopPhone.trim(),
          styles: const PosStyles(align: PosAlign.center),
        );
      }
      printer.hr();
      final heading = invoiceHeading.trim().isEmpty
          ? 'SALES INVOICE'
          : invoiceHeading.trim().toUpperCase();
      printer.text(
        heading,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      printer.feed(1);
    } else {
      printer.text(
        shopName,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      printer.hr();
    }

    // -- RECEIPT META --------------------------------------------------------
    metaRow('Receipt #', receiptNo);
    metaRow('Date', _fmtDate(dateTime));
    // Offline receipts carry a server-unconfirmed reference number.
    if (receiptNo.startsWith('OFF-')) {
      printer.text(
        'OFFLINE RECEIPT - PENDING SYNC',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }

    // -- CUSTOMER ------------------------------------------------------------
    if (sections.customer &&
        (cName.isNotEmpty ||
            cPhone.isNotEmpty ||
            cOtherPhones.isNotEmpty ||
            cAddr.isNotEmpty)) {
      printer.feed(1);
      printer.text('BILL TO', styles: boldLeft);
      if (cName.isNotEmpty) printer.text(cName);
      if (cPhone.isNotEmpty) printer.text(cPhone);
      if (cOtherPhones.isNotEmpty) printer.text(cOtherPhones.join(', '));
      if (cAddr.isNotEmpty) printer.text(cAddr);
    }
    printer.feed(1);

    // -- ITEM TABLE ----------------------------------------------------------
    printer.row([
      PosColumn(text: 'SL', width: slUnits, styles: boldLeft),
      PosColumn(text: 'ITEM NAME', width: 12 - slUnits, styles: boldLeft),
    ]);
    if (!operationalTicket) {
      printer.row([
        PosColumn(text: 'QTY', width: qtyUnits, styles: rightBold),
        PosColumn(text: 'RATE', width: rateUnits, styles: rightBold),
        if (showMrp)
          PosColumn(text: 'MRP', width: mrpUnits, styles: rightBold),
        PosColumn(text: 'AMOUNT', width: amountUnits, styles: rightBold),
        PosColumn(text: '', width: gutterUnits),
      ]);
    }
    printer.hr();

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final index = i + 1;

      if (sections.itemPrices) {
        final suffix = ThermalReceiptLayout.discountSuffix(
          it,
          itemDiscountDisplay,
          is58mm: is58mm,
        );
        final pack = ThermalReceiptLayout.packageSuffix(it);
        // The product name goes out as a full-width line so long names, the
        // package size and the compact discount label all wrap instead of
        // being clipped inside a narrow row() column.
        final nameLine = StringBuffer('$index  ${it.name}');
        if (pack.isNotEmpty) nameLine.write(' $pack');
        if (suffix.isNotEmpty) nameLine.write('  $suffix');
        printer.text(nameLine.toString());

        printer.row([
          PosColumn(
            text: ThermalReceiptLayout.qtyCell(it),
            width: qtyUnits,
            styles: right,
          ),
          PosColumn(
            text: ThermalReceiptLayout.rateCell(it, showMrp: showMrp),
            width: rateUnits,
            styles: right,
          ),
          if (showMrp)
            PosColumn(
              text: ThermalReceiptLayout.mrpCell(it),
              width: mrpUnits,
              styles: right,
            ),
          PosColumn(
            text: ThermalReceiptLayout.amountCell(it),
            width: amountUnits,
            styles: rightBold,
          ),
          PosColumn(text: '', width: gutterUnits),
        ]);

        if (itemDiscountDisplay == ItemDiscountDisplay.detailed &&
            it.hasDiscount) {
          printer.row([
            PosColumn(
              text: '  ${it.detailedDiscountLabel()}',
              width: detailLabelUnits,
            ),
            PosColumn(
              text: '-${_m(it.discountAmount)}',
              width: amountUnits,
              styles: right,
            ),
            PosColumn(text: '', width: gutterUnits),
          ]);
        }
        if (itemDiscountDisplay == ItemDiscountDisplay.detailed &&
            it.hasExtraDiscount) {
          printer.row([
            PosColumn(text: '  Extra Discount', width: detailLabelUnits),
            PosColumn(
              text: '-${_m(it.extraDiscountAmount.abs())}',
              width: amountUnits,
              styles: right,
            ),
            PosColumn(text: '', width: gutterUnits),
          ]);
        }
      } else {
        // Operational ticket: no prices, and the quantity is set double
        // height because it is the only figure a packer needs.
        printer.text('$index  ${it.name}', styles: boldLeft);
        printer.text(
          '  ${ThermalReceiptLayout.operationalQtyCell(it)}',
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        );
        if (it.hasPackagingSnapshot && it.packageConversionText.isNotEmpty) {
          printer.text('  ${it.packageConversionText}');
        }
      }
    }

    printer.hr();
    printer.row([
      PosColumn(
        text: ThermalReceiptLayout.totalItemsLabel(items, is58mm: is58mm),
        width: 5,
      ),
      PosColumn(
        text: ThermalReceiptLayout.totalQtyLabel(items, is58mm: is58mm),
        width: 6,
        styles: right,
      ),
      PosColumn(text: '', width: gutterUnits),
    ]);
    printer.hr();

    // -- TOTALS --------------------------------------------------------------
    if (sections.totalsBreakdown) {
      kv('Subtotal', _m(subtotal));
      if (discount > 0) kv('Discount', '-${_m(discount)}');
      if (tax > 0) kv('Tax', _m(tax));
      if (delivery > 0) kv('Shipping', _m(delivery));
    }

    if (!operationalTicket) {
      printer.hr();
      printer.row([
        PosColumn(
          text: 'TOTAL',
          width: 5,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: _m(grandTotal),
          width: 6,
          styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            align: PosAlign.right,
          ),
        ),
        PosColumn(text: '', width: gutterUnits),
      ]);
      printer.hr();

      // Payment method breakdown (split tender / non-cash tenders).
      final paymentsSnap = (meta?['payments_snapshot'] is List)
          ? (meta!['payments_snapshot'] as List)
          : (meta?['payments'] is List ? (meta!['payments'] as List) : const []);
      final showBreakdown = paymentsSnap.length > 1 ||
          (paymentsSnap.length == 1 &&
              paymentsSnap.first is Map &&
              (((paymentsSnap.first as Map)['method']?.toString() ?? 'cash') !=
                  'cash'));
      if (showBreakdown) {
        for (final p in paymentsSnap) {
          final map = (p is Map) ? p : const {};
          final label = (map['label'] ?? map['method'] ?? 'Paid').toString();
          final amt = (map['amount'] is num)
              ? (map['amount'] as num).toDouble()
              : double.tryParse((map['amount'] ?? '').toString()) ?? 0.0;
          final ref = (map['reference'] ?? '').toString().trim();
          kv(ref.isEmpty ? label : '$label ($ref)', _m(amt));
        }
      }

      if (cashReceived > 0) kv('Cash', _m(cashReceived));
      if (changeAmount > 0) kv('Change', _m(changeAmount));
    }

    if (!operationalTicket && showQr && _validQrUrl(qrUrl)) {
      printer.feed(1);
      printer.qrcode(
        qrUrl!.trim(),
        size: is58mm ? QRSize.size3 : QRSize.size4,
      );
      if (qrCaption.trim().isNotEmpty) {
        printer.text(
          qrCaption.trim().toUpperCase(),
          styles: const PosStyles(align: PosAlign.center),
        );
      }
    }

    if (sections.footer) {
      printer.feed(1);
      _writeFooterLines(
        printer,
        footerLines,
        footerLineStyles,
        devCreditEnabled: devCreditEnabled,
        devCreditText: devCreditText,
      );
    }

    printer.feed(2);
    printer.cut();
  }
  void _writeFooterLines(
    NetworkPrinter printer,
    List<String> footerLines,
    List<ReceiptFooterStyle> footerLineStyles, {
    bool devCreditEnabled = false,
    String devCreditText = '',
  }) {
    var printed = false;
    void writeLine(String text, ReceiptFooterStyle style) {
      final isLarge = style.size == ReceiptFooterTextSize.large;
      printer.text(
        text,
        styles: PosStyles(
          align: _posAlign(style.alignment),
          bold: style.bold,
          height: isLarge ? PosTextSize.size2 : PosTextSize.size1,
          width: isLarge ? PosTextSize.size2 : PosTextSize.size1,
          fontType: style.size == ReceiptFooterTextSize.small
              ? PosFontType.fontB
              : PosFontType.fontA,
        ),
      );
      printed = true;
    }

    for (var i = 0; i < footerLines.length; i++) {
      final text = PrintTextUtils.sanitizeFooterText(footerLines[i]);
      if (text.isEmpty) continue;
      final style = i < footerLineStyles.length
          ? footerLineStyles[i]
          : const ReceiptFooterStyle();
      writeLine(text, style);
    }
    // Master-Admin-controlled software credit line, printed last (below the
    // shop's own footer). A short hairline separates it from the merchant's
    // own footer so it reads as a quiet software credit, not part of their
    // message.
    if (devCreditEnabled) {
      final creditText = PrintTextUtils.sanitizeFooterText(devCreditText);
      if (creditText.isNotEmpty) {
        writeLine(
          '- - - - - - - -',
          const ReceiptFooterStyle(
            alignment: ReceiptFooterAlignment.center,
            bold: false,
            size: ReceiptFooterTextSize.small,
          ),
        );
        writeLine(
          creditText,
          const ReceiptFooterStyle(
            alignment: ReceiptFooterAlignment.center,
            bold: false,
            size: ReceiptFooterTextSize.small,
          ),
        );
      }
    }
    if (printed) printer.feed(1);
  }

  PosAlign _posAlign(ReceiptFooterAlignment alignment) {
    switch (alignment) {
      case ReceiptFooterAlignment.left:
        return PosAlign.left;
      case ReceiptFooterAlignment.right:
        return PosAlign.right;
      case ReceiptFooterAlignment.center:
        return PosAlign.center;
    }
  }

  static img.Image? _decodeLogoImage(String? data, int maxWidth) {
    final raw = (data ?? '').trim();
    if (!raw.startsWith('data:image/')) return null;
    final comma = raw.indexOf(',');
    if (comma <= 0 || comma >= raw.length - 1) return null;
    try {
      final bytes = base64Decode(raw.substring(comma + 1));
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      if (decoded.width <= maxWidth) return decoded;
      return img.copyResize(decoded, width: maxWidth);
    } catch (_) {
      return null;
    }
  }

  static bool _validQrUrl(String? value) {
    final uri = Uri.tryParse((value ?? '').trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static String _fmtDate(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} "
      "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

  static String _m(num v) => v.toStringAsFixed(2);
}
