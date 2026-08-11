import 'dart:convert';
import 'dart:typed_data';
import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

typedef ReceiptItem = SaleReceiptItem;

class ReceiptPreviewService {
  ReceiptPreviewService._();
  static final instance = ReceiptPreviewService._();

  /// Thermal roll page format used by PDF preview and local Windows printing.
  ///
  /// PdfPageFormat.roll57/roll80 include a built-in 5 mm margin. The receipt
  /// renderer already owns its content margins, so keeping those format
  /// margins can make native printer layouts add unwanted whitespace.
  PdfPageFormat pageFormatForPaperWidth(String paperWidth) {
    switch (paperWidth.toLowerCase()) {
      case 'a4':
        return PdfPageFormat.a4;
      case 'a5':
        return PdfPageFormat.a5;
      case 'letter':
        return PdfPageFormat.letter;
      case 'mm58':
        return PdfPageFormat.roll57.copyWith(
          marginTop: 0,
          marginBottom: 0,
          marginLeft: 0,
          marginRight: 0,
        );
      default:
        return PdfPageFormat.roll80.copyWith(
          marginTop: 0,
          marginBottom: 0,
          marginLeft: 0,
          marginRight: 0,
        );
    }
  }

  /// Renders exactly what [sections] says to show — same section toggles
  /// the real ESC/POS print uses, so a PDF preview never shows something
  /// that wouldn't actually print.
  Future<void> previewReceipt({
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    required String receiptNo,
    required DateTime dateTime,
    required List<ReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    Map<String, dynamic>? meta,
    InvoiceSections sections = const InvoiceSections(
      header: true,
      customer: true,
      totalsBreakdown: true,
      footer: true,
    ),
    String paperWidth = 'mm80',
    List<String> footerLines = const [],
    String? receiptHeader,
    String invoiceHeading = 'SALES INVOICE',
    bool showLogo = false,
    String? logoData,
    bool showQr = false,
    String? qrUrl,
    String qrCaption = 'Scan to review us',
    bool layoutForPrinting = true,
  }) async {
    final bytes = await buildReceiptPdf(
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
      meta: meta,
      sections: sections,
      paperWidth: paperWidth,
      footerLines: footerLines,
      receiptHeader: receiptHeader,
      invoiceHeading: invoiceHeading,
      showLogo: showLogo,
      logoData: logoData,
      showQr: showQr,
      qrUrl: qrUrl,
      qrCaption: qrCaption,
    );

    if (layoutForPrinting) {
      await Printing.layoutPdf(
        name: 'Receipt $receiptNo',
        format: pageFormatForPaperWidth(paperWidth),
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
    }
  }

  /// Same renderer as [previewReceipt] but just returns the bytes, for the
  /// template preview screen to display inline instead of opening the
  /// system print dialog every time someone switches templates.
  Future<Uint8List> buildReceiptPdf({
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    required String receiptNo,
    required DateTime dateTime,
    required List<ReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    Map<String, dynamic>? meta,
    required InvoiceSections sections,
    String paperWidth = 'mm80',
    List<String> footerLines = const [],
    String? receiptHeader,
    String invoiceHeading = 'SALES INVOICE',
    bool showLogo = false,
    String? logoData,
    bool showQr = false,
    String? qrUrl,
    String qrCaption = 'Scan to review us',
  }) async {
    // --- extract meta safely ---
    final snapRaw = meta?["customer_snapshot"];
    final snap = (snapRaw is Map) ? snapRaw.cast<String, dynamic>() : <String, dynamic>{};

    final cName = (snap["name"] ?? "").toString().trim();
    final cPhone = (snap["phone"] ?? "").toString().trim();
    final cAddr = (snap["address"] ?? "").toString().trim();

    final delivery = (meta?["delivery"] is num)
        ? (meta!["delivery"] as num).toDouble()
        : double.tryParse((meta?["delivery"] ?? "").toString()) ?? 0.0;

    final cashReceived = (meta?["cash_received"] is num)
        ? (meta!["cash_received"] as num).toDouble()
        : double.tryParse((meta?["cash_received"] ?? "").toString()) ?? 0.0;
    final changeAmount = (meta?["change_amount"] is num)
        ? (meta!["change_amount"] as num).toDouble()
        : double.tryParse((meta?["change_amount"] ?? "").toString()) ?? 0.0;

    // Payment method breakdown (split tender), e.g. Cash 1000 + Bank 500.
    final paymentsSnap = (meta?["payments_snapshot"] is List)
        ? (meta!["payments_snapshot"] as List)
        : (meta?["payments"] is List ? (meta!["payments"] as List) : const []);

    if (const {'a4', 'a5', 'letter'}.contains(paperWidth.toLowerCase())) {
      return _buildStandardInvoicePdf(
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
        meta: meta,
        paperWidth: paperWidth,
        footerLines: footerLines,
        invoiceHeading: invoiceHeading,
        showLogo: showLogo,
        logoData: logoData,
        showQr: showQr,
        qrUrl: qrUrl,
        qrCaption: qrCaption,
      );
    }

    final doc = pw.Document();
    final pageFormat = pageFormatForPaperWidth(paperWidth);
    final is58mm = paperWidth == 'mm58';

    // Windows thermal drivers often reserve a small non-printable area on the
    // physical left edge. Keep CounterIQ's own left inset almost zero and
    // reserve a little more room on the right instead. This shifts the receipt
    // content left without letting the Total column run into the right edge.
    // Top is intentionally zero: any remaining leading paper on a real printer
    // is then the printer/driver's own feed area rather than template padding.
    final receiptMargin = is58mm
        ? const pw.EdgeInsets.fromLTRB(1, 0, 12, 6)
        : const pw.EdgeInsets.fromLTRB(1, 0, 14, 8);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: receiptMargin,
        build: (_) {
          pw.Widget divider() => pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 5),
            height: 0.8,
            color: PdfColors.grey400,
          );

          pw.Widget dashedDivider() => pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Row(
              children: List.generate(
                32,
                (_) => pw.Expanded(
                  child: pw.Container(
                    height: 0.8,
                    margin: const pw.EdgeInsets.symmetric(horizontal: 1),
                    color: PdfColors.grey500,
                  ),
                ),
              ),
            ),
          );

          final pw.TextStyle shopStyle = pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          );
          final pw.TextStyle bold = pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          );
          final pw.TextStyle columnHeader = pw.TextStyle(
            fontSize: is58mm ? 8 : 8.5,
            fontWeight: pw.FontWeight.bold,
          );
          const pw.TextStyle normal = pw.TextStyle(fontSize: 9);
          const pw.TextStyle small = pw.TextStyle(fontSize: 8);

          final secondaryHeader = (receiptHeader ?? '').trim();

          final String dt =
              "${dateTime.day.toString().padLeft(2, '0')}/"
              "${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} "
              "${dateTime.hour.toString().padLeft(2, '0')}:"
              "${dateTime.minute.toString().padLeft(2, '0')}";

          // Keep right-aligned money slightly inside the printable edge. Some
          // Windows thermal drivers clip the last few dots even when the page
          // width is correct. We keep the physical page margins unchanged and
          // pull only monetary values inward.
          // Keep the entire money/Total column farther away from the physical
          // right edge. On some 80 mm thermal heads the final few millimetres
          // print noticeably lighter even though they are technically inside
          // the driver's printable area. This moves only the right-aligned
          // monetary column left; product names, calculation indentation, and
          // the page's balanced physical margins stay exactly as they are.
          final double moneyRightInset = is58mm ? 10 : 17;
          final double detailLeftInset = is58mm ? 3 : 4;

          pw.Widget rightMoney(String value, pw.TextStyle style) => pw.Padding(
            padding: pw.EdgeInsets.only(right: moneyRightInset),
            child: pw.Text(value, style: style, textAlign: pw.TextAlign.right),
          );

          pw.Widget kv(String k, String v, {bool bold2 = false}) => pw.Row(
            children: [
              pw.Expanded(child: pw.Text(k, style: bold2 ? bold : normal)),
              rightMoney(v, bold2 ? bold : normal),
            ],
          );

          final bool hasCustomerInfo =
              sections.customer && (cName.isNotEmpty || cPhone.isNotEmpty || cAddr.isNotEmpty);

          final activeFooterLines = sections.footer
              ? footerLines.where((l) => l.trim().isNotEmpty).toList()
              : <String>[];

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── HEADER ────────────────────────────────────────────────────
              // Secondary copies get their own explicit operational heading
              // (KITCHEN COPY / PACKING COPY / BAR COPY / etc.) instead of
              // mutating the business name.
              if (secondaryHeader.isNotEmpty) ...[
                pw.Center(child: pw.Text(secondaryHeader, style: shopStyle)),
                pw.SizedBox(height: 2),
              ],
              if (sections.header) ...[
                if (showLogo && _decodeLogo(logoData) != null) ...[
                  pw.Center(
                    child: pw.Container(
                      height: is58mm ? 34 : 42,
                      child: pw.Image(
                        pw.MemoryImage(_decodeLogo(logoData)!),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 3),
                ],
                pw.Center(child: pw.Text(shopName, style: shopStyle)),
                if (shopAddress != null && shopAddress.trim().isNotEmpty)
                  pw.Center(child: pw.Text(shopAddress, style: small)),
                if (shopPhone != null && shopPhone.trim().isNotEmpty)
                  pw.Center(child: pw.Text(shopPhone, style: small)),
                divider(),
              ] else ...[
                pw.Center(child: pw.Text(shopName, style: bold)),
                if (secondaryHeader.isNotEmpty) divider(),
              ],

              // ── RECEIPT META ───────────────────────────────────────────────
              pw.Center(child: pw.Text("Receipt# $receiptNo", style: bold)),
              // Show a subtle "Offline Receipt / Pending Sync" note when the
              // receipt number is an offline reference (starts with OFF-).
              if (receiptNo.startsWith('OFF-'))
                pw.Center(
                  child: pw.Text(
                    "Offline Receipt — Pending Sync",
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              pw.Center(child: pw.Text(dt, style: small)),
              divider(),

              // ── CUSTOMER ───────────────────────────────────────────────────
              if (hasCustomerInfo) ...[
                if (cName.isNotEmpty) pw.Text("Customer: $cName", style: normal),
                if (cPhone.isNotEmpty) pw.Text("Phone: $cPhone", style: small),
                if (cAddr.isNotEmpty) pw.Text("Address: $cAddr", style: small),
                divider(),
              ],

              // ── ITEMS ──────────────────────────────────────────────────────
              // Thermal receipts read better when the product gets the full
              // paper width. Financial detail lives on an indented second row
              // instead of squeezing Item / Price / Qty / Total into four
              // narrow columns.
              if (sections.itemPrices) ...[
                pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text('ITEM', style: columnHeader)),
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: moneyRightInset),
                      child: pw.Text('TOTAL', style: columnHeader),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                ...items.map(
                  (it) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Text(it.name, style: normal),
                        pw.SizedBox(height: 1),
                        pw.Padding(
                          padding: pw.EdgeInsets.only(left: detailLeftInset),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Expanded(
                                child: pw.Text(
                                  '${_q(it.qty)} x ${_m(it.price)}',
                                  style: small,
                                ),
                              ),
                              pw.SizedBox(width: is58mm ? 3 : 4),
                              rightMoney(_m(it.total), normal),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                pw.Text('ITEMS', style: columnHeader),
                pw.SizedBox(height: 4),
                ...items.map(
                  (it) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Text(
                      '${_q(it.qty)} x ${it.name}',
                      style: bold,
                    ),
                  ),
                ),
              ],

              dashedDivider(),

              // ── TOTALS ─────────────────────────────────────────────────────
              if (sections.totalsBreakdown) ...[
                kv("Subtotal", _m(subtotal), bold2: false),
                if (discount > 0) kv("Discount", "-${_m(discount)}"),
                if (tax > 0) kv("Tax", _m(tax)),
                if (delivery > 0) kv("Shipping Charges", _m(delivery)),
                divider(),
              ],

              // Grand total always shows.
              kv("Grand Total", _m(grandTotal), bold2: true),

              // Payment method breakdown — printed for split tenders or any
              // non-cash tender (e.g. Cash 1000, Bank 500, KNET 250 (TXN…)).
              if (paymentsSnap.length > 1 ||
                  (paymentsSnap.length == 1 &&
                      (paymentsSnap.first is Map) &&
                      (((paymentsSnap.first as Map)['method']?.toString() ?? 'cash') != 'cash')))
                ...paymentsSnap.map((p) {
                  final map = (p is Map) ? p : const <String, dynamic>{};
                  final label = (map['label'] ?? map['method'] ?? 'Paid').toString();
                  final amt = (map['amount'] is num)
                      ? (map['amount'] as num).toDouble()
                      : double.tryParse((map['amount'] ?? '').toString()) ?? 0.0;
                  final ref = (map['reference'] ?? '').toString().trim();
                  return kv(ref.isEmpty ? label : "$label ($ref)", _m(amt));
                }),

              if (cashReceived > 0) kv("Cash", _m(cashReceived), bold2: true),
              if (changeAmount > 0) kv("Change", _m(changeAmount), bold2: true),

              // ── OPTIONAL CUSTOMER QR ──────────────────────────────────────────
              if (showQr && _validQrUrl(qrUrl)) ...[
                divider(),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrUrl!.trim(),
                    width: is58mm ? 54 : 64,
                    height: is58mm ? 54 : 64,
                  ),
                ),
                if (qrCaption.trim().isNotEmpty)
                  pw.Center(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(qrCaption.trim(), style: small),
                    ),
                  ),
              ],

              // ── FOOTER ─────────────────────────────────────────────────────
              if (activeFooterLines.isNotEmpty) ...[
                divider(),
                ...activeFooterLines.map(
                  (line) => pw.Center(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(line, style: bold, textAlign: pw.TextAlign.center),
                    ),
                  ),
                ),
              ],

              pw.SizedBox(height: 8),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _buildStandardInvoicePdf({
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    required String receiptNo,
    required DateTime dateTime,
    required List<ReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    Map<String, dynamic>? meta,
    required String paperWidth,
    required List<String> footerLines,
    required String invoiceHeading,
    required bool showLogo,
    String? logoData,
    required bool showQr,
    String? qrUrl,
    required String qrCaption,
  }) async {
    final doc = pw.Document();
    final format = pageFormatForPaperWidth(paperWidth);
    final isA5 = paperWidth.toLowerCase() == 'a5';
    final accent = PdfColor.fromInt(0xFF0F766E);
    final accentSoft = PdfColor.fromInt(0xFFF0FDFA);
    final border = PdfColor.fromInt(0xFFD8E1E7);
    final ink = PdfColor.fromInt(0xFF172033);
    final muted = PdfColor.fromInt(0xFF617083);
    final logoBytes = showLogo ? _decodeLogo(logoData) : null;

    final customerRaw = meta?['customer_snapshot'];
    final customer = customerRaw is Map
        ? customerRaw.cast<String, dynamic>()
        : <String, dynamic>{};
    final customerName = (customer['name'] ?? '').toString().trim();
    final customerPhone = (customer['phone'] ?? '').toString().trim();
    final customerAddress = (customer['address'] ?? '').toString().trim();
    final effectiveCustomer = customerName.isEmpty ? 'Walk-in Customer' : customerName;

    double numericMeta(String key) {
      final raw = meta?[key];
      if (raw is num) return raw.toDouble();
      return double.tryParse((raw ?? '').toString()) ?? 0;
    }

    final delivery = numericMeta('delivery');
    final cashReceived = numericMeta('cash_received');
    final change = numericMeta('change_amount');
    final paymentRaw = meta?['payments_snapshot'] is List
        ? meta!['payments_snapshot'] as List
        : (meta?['payments'] is List ? meta!['payments'] as List : const []);
    final payments = <Map<String, dynamic>>[];
    for (final raw in paymentRaw) {
      if (raw is Map) payments.add(raw.cast<String, dynamic>());
    }
    final paidFromPayments = payments.fold<double>(0, (sum, p) {
      final raw = p['amount'];
      return sum + (raw is num ? raw.toDouble() : double.tryParse((raw ?? '').toString()) ?? 0);
    });
    final paid = paidFromPayments > 0 ? paidFromPayments : cashReceived;
    final balanceDue = (grandTotal - paid).clamp(0, double.infinity).toDouble();

    String dateOnly(DateTime d) =>
        "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
    String timeOnly(DateTime d) =>
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

    pw.TextStyle textStyle(double size, {bool bold = false, PdfColor? color}) => pw.TextStyle(
          fontSize: size,
          color: color ?? ink,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        );

    pw.Widget labelValue(String label, String value, {bool strong = false, bool accentValue = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(label, style: textStyle(isA5 ? 8.5 : 9.5, bold: strong, color: muted))),
            pw.Text(
              value,
              style: textStyle(isA5 ? 9 : 10, bold: strong || accentValue, color: accentValue ? accent : ink),
              textAlign: pw.TextAlign.right,
            ),
          ],
        ),
      );
    }

    pw.Widget tableCell(
      String text, {
      bool header = false,
      pw.TextAlign align = pw.TextAlign.left,
      double? fontSize,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 3 : 5, vertical: isA5 ? 5 : 6),
        child: pw.Text(
          text,
          style: textStyle(fontSize ?? (isA5 ? 7.7 : 8.8), bold: header, color: header ? PdfColors.white : ink),
          textAlign: align,
        ),
      );
    }

    pw.Widget productCell(String name) {
      final parts = name.split(' / ').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
      if (parts.length < 2) return tableCell(name);
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 3 : 5, vertical: isA5 ? 5 : 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(parts.first, style: textStyle(isA5 ? 7.7 : 8.8, bold: true)),
            pw.SizedBox(height: 1.5),
            pw.Text(parts.skip(1).join(' • '), style: textStyle(isA5 ? 6.8 : 7.8, color: muted)),
          ],
        ),
      );
    }

    final heading = invoiceHeading.trim().isEmpty ? 'SALES INVOICE' : invoiceHeading.trim();
    final activeFooterLines = footerLines.where((line) => line.trim().isNotEmpty).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: pw.EdgeInsets.fromLTRB(isA5 ? 20 : 28, isA5 ? 20 : 28, isA5 ? 20 : 28, isA5 ? 20 : 28),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: border, width: .6))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Thank you for your business!', style: textStyle(isA5 ? 7.5 : 8.5, bold: true, color: accent)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: textStyle(isA5 ? 7 : 8, color: muted)),
            ],
          ),
        ),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoBytes != null) ...[
                pw.Container(
                  width: isA5 ? 54 : 70,
                  height: isA5 ? 44 : 54,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: isA5 ? 8 : 12),
              ],
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shopName, style: textStyle(isA5 ? 15 : 18, bold: true)),
                    if ((shopAddress ?? '').trim().isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(shopAddress!.trim(), style: textStyle(isA5 ? 7.5 : 8.5, color: muted)),
                    ],
                    if ((shopPhone ?? '').trim().isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(shopPhone!.trim(), style: textStyle(isA5 ? 7.5 : 8.5, color: muted)),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Container(
                width: isA5 ? 126 : 160,
                padding: pw.EdgeInsets.all(isA5 ? 8 : 10),
                decoration: pw.BoxDecoration(
                  color: accentSoft,
                  border: pw.Border.all(color: accent, width: .8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(heading, style: textStyle(isA5 ? 11 : 13, bold: true, color: accent), textAlign: pw.TextAlign.right),
                    pw.SizedBox(height: 6),
                    labelValue('Invoice No.', receiptNo, strong: true),
                    labelValue('Date', dateOnly(dateTime)),
                    labelValue('Time', timeOnly(dateTime)),
                    if (receiptNo.startsWith('OFF-'))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 4),
                        child: pw.Text('Offline - Pending Sync', style: textStyle(isA5 ? 6.5 : 7.5, bold: true, color: accent), textAlign: pw.TextAlign.right),
                      ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: isA5 ? 12 : 16),
          pw.Container(height: 1.2, color: accent),
          pw.SizedBox(height: isA5 ? 10 : 13),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(isA5 ? 8 : 10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
              border: pw.Border.all(color: border, width: .6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('CUSTOMER', style: textStyle(isA5 ? 8 : 9, bold: true, color: accent)),
                pw.SizedBox(height: 4),
                pw.Text(effectiveCustomer, style: textStyle(isA5 ? 9.5 : 10.5, bold: true)),
                if (customerPhone.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text('Phone: $customerPhone', style: textStyle(isA5 ? 7.5 : 8.5, color: muted))),
                if (customerAddress.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text('Address: $customerAddress', style: textStyle(isA5 ? 7.5 : 8.5, color: muted))),
              ],
            ),
          ),
          pw.SizedBox(height: isA5 ? 10 : 14),
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: border, width: .45),
              bottom: pw.BorderSide(color: border, width: .7),
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(22),
              1: const pw.FlexColumnWidth(4.4),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(.9),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(1.35),
              6: const pw.FlexColumnWidth(1.65),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: accent),
                children: [
                  tableCell('#', header: true),
                  tableCell('PRODUCT', header: true),
                  tableCell('UNIT', header: true, align: pw.TextAlign.center),
                  tableCell('QTY', header: true, align: pw.TextAlign.right),
                  tableCell('UNIT PRICE', header: true, align: pw.TextAlign.right),
                  tableCell('DISCOUNT', header: true, align: pw.TextAlign.right),
                  tableCell('AMOUNT', header: true, align: pw.TextAlign.right),
                ],
              ),
              ...List.generate(items.length, (index) {
                final item = items[index];
                return pw.TableRow(
                  children: [
                    tableCell('${index + 1}'),
                    productCell(item.name),
                    tableCell(item.unitName.isEmpty ? '-' : item.unitName, align: pw.TextAlign.center),
                    tableCell(_q(item.qty), align: pw.TextAlign.right),
                    tableCell(_m(item.price), align: pw.TextAlign.right),
                    tableCell(_m(item.discountAmount), align: pw.TextAlign.right),
                    tableCell(_m(item.total), align: pw.TextAlign.right),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: isA5 ? 10 : 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (payments.isNotEmpty) ...[
                      pw.Text('PAYMENT DETAILS', style: textStyle(isA5 ? 8 : 9, bold: true, color: accent)),
                      pw.SizedBox(height: 5),
                      ...payments.map((p) {
                        final label = (p['label'] ?? p['method'] ?? 'Payment').toString();
                        final ref = (p['reference'] ?? '').toString().trim();
                        final raw = p['amount'];
                        final amount = raw is num ? raw.toDouble() : double.tryParse((raw ?? '').toString()) ?? 0;
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 3),
                          child: pw.Text("${ref.isEmpty ? label : '$label ($ref)'}: ${_m(amount)}", style: textStyle(isA5 ? 7.5 : 8.5)),
                        );
                      }),
                    ],
                    if (activeFooterLines.isNotEmpty) ...[
                      pw.SizedBox(height: payments.isEmpty ? 0 : 10),
                      ...activeFooterLines.map((line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 3),
                            child: pw.Text(line.trim(), style: textStyle(isA5 ? 7.5 : 8.5, color: muted)),
                          )),
                    ],
                    if (showQr && _validQrUrl(qrUrl)) ...[
                      pw.SizedBox(height: 10),
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: qrUrl!.trim(),
                            width: isA5 ? 58 : 68,
                            height: isA5 ? 58 : 68,
                          ),
                          if (qrCaption.trim().isNotEmpty) ...[
                            pw.SizedBox(width: 8),
                            pw.Expanded(child: pw.Text(qrCaption.trim(), style: textStyle(isA5 ? 7.5 : 8.5, bold: true, color: accent))),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: isA5 ? 10 : 16),
              pw.Container(
                width: isA5 ? 155 : 205,
                padding: pw.EdgeInsets.all(isA5 ? 8 : 10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF8FAFC),
                  border: pw.Border.all(color: border, width: .6),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    labelValue('Subtotal', _m(subtotal)),
                    if (discount > 0) labelValue('Discount', '-${_m(discount)}'),
                    if (tax > 0) labelValue('Tax', _m(tax)),
                    if (delivery > 0) labelValue('Delivery', _m(delivery)),
                    pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 5), height: .8, color: border),
                    labelValue('TOTAL', _m(grandTotal), strong: true, accentValue: true),
                    if (paid > 0) labelValue('Paid', _m(paid), strong: true),
                    if (change > 0) labelValue('Change', _m(change), strong: true, accentValue: true),
                    if (balanceDue > .004) labelValue('Balance Due', _m(balanceDue), strong: true, accentValue: true),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
        ],
      ),
    );
    return doc.save();
  }

  static Uint8List? _decodeLogo(String? data) {
    final raw = (data ?? '').trim();
    if (raw.isEmpty || !raw.startsWith('data:image/')) return null;
    final comma = raw.indexOf(',');
    if (comma <= 0 || comma == raw.length - 1) return null;
    try {
      return base64Decode(raw.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static bool _validQrUrl(String? value) {
    final uri = Uri.tryParse((value ?? '').trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  static String _m(num v) => v.toStringAsFixed(2);
  static String _q(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toString();
}
