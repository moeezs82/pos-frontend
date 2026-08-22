import 'dart:convert';
import 'dart:typed_data';
import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/models/sale_receipt_item.dart';
import 'package:enterprise_pos/services/pdf_arabic_font_loader.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

typedef ReceiptItem = SaleReceiptItem;

class _ReceiptTextPart {
  final String text;
  final bool isArabic;

  const _ReceiptTextPart(this.text, this.isArabic);
}

class ReceiptPreviewService {
  ReceiptPreviewService._();
  static final instance = ReceiptPreviewService._();

  static final RegExp _arabicTextPattern = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  bool _containsArabic(String value) => _arabicTextPattern.hasMatch(value);

  /// Splits configured bilingual text on `|` and orders the language segments
  /// for the active template. The separator is a configuration delimiter, not
  /// printable content. A single-language value is preserved as-is.
  List<_ReceiptTextPart> _configuredTextParts(
    String raw, {
    required bool arabicFirst,
  }) {
    final values = raw
        .split('|')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (values.isEmpty) return const <_ReceiptTextPart>[];

    final parts = values
        .map((part) => _ReceiptTextPart(part, _containsArabic(part)))
        .toList();
    if (parts.length < 2) return parts;

    final hasArabic = parts.any((part) => part.isArabic);
    final hasOther = parts.any((part) => !part.isArabic);
    if (!hasArabic || !hasOther) return parts;

    final arabic = parts.where((part) => part.isArabic);
    final other = parts.where((part) => !part.isArabic);
    return arabicFirst
        ? <_ReceiptTextPart>[...arabic, ...other]
        : <_ReceiptTextPart>[...other, ...arabic];
  }

  String? _configuredLanguagePart(String raw, {required bool arabic}) {
    for (final part in _configuredTextParts(raw, arabicFirst: arabic)) {
      if (part.isArabic == arabic) return part.text;
    }
    return null;
  }

  pw.Widget _configuredPdfText(
    String raw, {
    required ArabicPdfFonts fonts,
    required bool arabicFirst,
    required double fontSize,
    bool bold = false,
    PdfColor? color,
    pw.TextAlign align = pw.TextAlign.center,
    double lineGap = 1,
  }) {
    final parts = _configuredTextParts(raw, arabicFirst: arabicFirst);
    if (parts.isEmpty) return pw.SizedBox();

    final textStyle = pw.TextStyle(
      font: bold ? fonts.bold : fonts.regular,
      fontSize: fontSize,
      color: color ?? PdfColors.black,
    );

    pw.Widget partWidget(_ReceiptTextPart part) => pw.Text(
          part.text,
          style: textStyle,
          textDirection:
              part.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          textAlign: align,
        );

    if (parts.length == 1) return partWidget(parts.first);

    final children = <pw.Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0 && lineGap > 0) children.add(pw.SizedBox(height: lineGap));
      children.add(partWidget(parts[i]));
    }

    final crossAxisAlignment = switch (align) {
      pw.TextAlign.left => pw.CrossAxisAlignment.start,
      pw.TextAlign.right => pw.CrossAxisAlignment.end,
      _ => pw.CrossAxisAlignment.center,
    };

    return pw.Column(
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );
  }

  String _customerDisplayName(
    Map<String, dynamic> customer, {
    String fallback = '',
  }) {
    final name = (customer['name'] ?? '').toString().trim();
    final code = (customer['customer_code'] ?? '').toString().trim();
    if (code.isNotEmpty && name.isNotEmpty) return '($code) $name';
    if (name.isNotEmpty) return name;
    if (code.isNotEmpty) return '($code)';
    return fallback;
  }

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
    InvoiceTemplate? template,
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
      template: template,
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
    InvoiceTemplate? template,
  }) async {
    // --- extract meta safely ---
    final snapRaw = meta?["customer_snapshot"];
    final snap = (snapRaw is Map) ? snapRaw.cast<String, dynamic>() : <String, dynamic>{};

    final cName = _customerDisplayName(snap);
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

    if (template == InvoiceTemplate.arabicStandardInvoice) {
      return _buildArabicStandardInvoicePdf(
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

    if (template == InvoiceTemplate.arabicThermal) {
      return _buildArabicThermalPdf(
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
        showLogo: showLogo,
        logoData: logoData,
        showQr: showQr,
        qrUrl: qrUrl,
        qrCaption: qrCaption,
      );
    }

    if (template == InvoiceTemplate.standardInvoice ||
        (template == null && const {'a4', 'a5', 'letter'}.contains(paperWidth.toLowerCase()))) {
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

  Future<ArabicPdfFonts> _loadArabicFonts() async {
    final system = await loadSystemArabicPdfFonts();
    if (system != null) return system;

    // Web/non-IO fallback. CounterIQ Windows workstations normally resolve an
    // installed Segoe UI/Tahoma/Arial font above, so Arabic printing remains
    // fully offline on the primary desktop target.
    try {
      final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
      final bold = await PdfGoogleFonts.notoNaskhArabicBold();
      return ArabicPdfFonts(regular: regular, bold: bold);
    } catch (_) {
      throw Exception(
        'Arabic print template needs an Arabic-capable font. '
        'Install Segoe UI, Tahoma, Arial, or Noto Arabic on this device.',
      );
    }
  }

  String _arabicInvoiceHeading(String english) {
    switch (english.trim().toUpperCase()) {
      case 'TAX INVOICE':
        return 'فاتورة ضريبية';
      case 'CASH INVOICE':
        return 'فاتورة نقدية';
      case 'RECEIPT':
        return 'إيصال';
      case 'INVOICE':
        return 'فاتورة';
      default:
        return 'فاتورة بيع';
    }
  }

  String _arabicPaymentLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'credit card':
      case 'debit card':
        return 'بطاقة';
      case 'bank':
      case 'bank transfer':
        return 'تحويل بنكي';
      case 'knet':
        return 'كي نت';
      case 'cheque':
      case 'check':
        return 'شيك';
      default:
        return 'دفعة';
    }
  }

  Future<Uint8List> _buildArabicThermalPdf({
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
    required bool showLogo,
    String? logoData,
    required bool showQr,
    String? qrUrl,
    required String qrCaption,
  }) async {
    final fonts = await _loadArabicFonts();
    final doc = pw.Document();
    final is58 = paperWidth.toLowerCase() == 'mm58';
    final widthMm = is58 ? 58.0 : 80.0;
    final accent = PdfColor.fromInt(0xFF0F766E);
    final muted = PdfColor.fromInt(0xFF5F6B76);
    final border = PdfColor.fromInt(0xFFD7DEE3);
    final logoBytes = showLogo ? _decodeLogo(logoData) : null;

    final customerRaw = meta?['customer_snapshot'];
    final customer = customerRaw is Map
        ? customerRaw.cast<String, dynamic>()
        : <String, dynamic>{};
    final customerName = _customerDisplayName(customer);
    final customerPhone = (customer['phone'] ?? '').toString().trim();
    final customerAddress = (customer['address'] ?? '').toString().trim();

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
      return sum +
          (raw is num
              ? raw.toDouble()
              : double.tryParse((raw ?? '').toString()) ?? 0);
    });
    final paid = paidFromPayments > 0 ? paidFromPayments : cashReceived;
    final balanceDue = (grandTotal - paid).clamp(0, double.infinity).toDouble();

    final itemHeightMm = items.fold<double>(0, (sum, item) {
      final hasArabic = item.effectiveSecondaryName.isNotEmpty;
      return sum + (is58 ? (hasArabic ? 20 : 15) : (hasArabic ? 16 : 12));
    });
    final customerHeight = customerName.isNotEmpty || customerPhone.isNotEmpty || customerAddress.isNotEmpty
        ? (is58 ? 25.0 : 20.0)
        : 0.0;
    final paymentHeight = payments.isEmpty ? 0.0 : 13.0 + payments.length * 6.0;
    final qrHeight = showQr && _validQrUrl(qrUrl) ? (is58 ? 35.0 : 40.0) : 0.0;
    final footerHeight = footerLines.where((e) => e.trim().isNotEmpty).length * 5.0 + 14.0;
    final estimatedHeightMm = (92.0 + customerHeight + itemHeightMm + 50.0 + paymentHeight + qrHeight + footerHeight)
        .clamp(150.0, 3000.0)
        .toDouble();

    final format = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      estimatedHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );

    pw.TextStyle style(
      double size, {
      bool bold = false,
      PdfColor? color,
    }) =>
        pw.TextStyle(
          font: bold ? fonts.bold : fonts.regular,
          fontSize: size,
          color: color ?? PdfColors.black,
        );

    pw.Widget arText(
      String text, {
      double size = 9,
      bool bold = true,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.right,
    }) =>
        pw.Text(
          text,
          style: style(size, bold: bold, color: color),
          textDirection: pw.TextDirection.rtl,
          textAlign: align,
        );

    pw.Widget bilingualLabel(
      String ar,
      String en, {
      double arSize = 8.5,
      double enSize = 6.8,
    }) =>
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            arText(ar, size: arSize, bold: true),
            pw.Text(
              en,
              style: style(enSize, color: muted),
              textAlign: pw.TextAlign.right,
            ),
          ],
        );

    pw.Widget divider() => pw.Container(
          height: .7,
          margin: const pw.EdgeInsets.symmetric(vertical: 5),
          color: border,
        );

    pw.Widget valueRow(
      String ar,
      String en,
      String value, {
      bool strong = false,
    }) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: _configuredPdfText(
                  value,
                  fonts: fonts,
                  arabicFirst: true,
                  fontSize: is58 ? 7.2 : 8.2,
                  bold: strong,
                  align: pw.TextAlign.left,
                  lineGap: .6,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.SizedBox(
                width: is58 ? 72 : 94,
                child: bilingualLabel(ar, en),
              ),
            ],
          ),
        );

    final dateText =
        '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
    final timeText =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    final activeFooterLines = footerLines.where((e) => e.trim().isNotEmpty).toList();

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.fromLTRB(is58 ? 8 : 10, 8, is58 ? 8 : 10, 8),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logoBytes != null) ...[
              pw.Center(
                child: pw.SizedBox(
                  height: is58 ? 32 : 40,
                  child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 3),
            ],
            _configuredPdfText(
              shopName,
              fonts: fonts,
              arabicFirst: true,
              fontSize: is58 ? 12 : 14,
              bold: true,
              color: accent,
              align: pw.TextAlign.center,
              lineGap: 1.2,
            ),
            if ((shopAddress ?? '').trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: _configuredPdfText(
                  shopAddress!.trim(),
                  fonts: fonts,
                  arabicFirst: true,
                  fontSize: is58 ? 6.6 : 7.6,
                  color: muted,
                  align: pw.TextAlign.center,
                  lineGap: .8,
                ),
              ),
            if ((shopPhone ?? '').trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1),
                child: pw.Text(
                  shopPhone!.trim(),
                  style: style(is58 ? 6.6 : 7.6, color: muted),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            pw.SizedBox(height: 5),
            arText('فاتورة بيع', size: is58 ? 12 : 14, bold: true, color: accent, align: pw.TextAlign.center),
            pw.Text(
              'SALES INVOICE',
              style: style(is58 ? 7.5 : 8.5, bold: true, color: accent),
              textAlign: pw.TextAlign.center,
            ),
            divider(),
            valueRow('رقم الفاتورة', 'Invoice No.', receiptNo, strong: true),
            valueRow('التاريخ', 'Date', dateText),
            valueRow('الوقت', 'Time', timeText),
            if (receiptNo.startsWith('OFF-'))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Column(
                  children: [
                    arText('غير متصل - بانتظار المزامنة', size: 7, bold: true, color: accent, align: pw.TextAlign.center),
                    pw.Text('Offline - Pending Sync', style: style(6, color: muted), textAlign: pw.TextAlign.center),
                  ],
                ),
              ),
            if (customerName.isNotEmpty || customerPhone.isNotEmpty || customerAddress.isNotEmpty) ...[
              divider(),
              valueRow(
                'العميل',
                'Customer',
                customerName.isEmpty ? 'Walk-in Customer' : customerName,
                strong: true,
              ),
              if (customerPhone.isNotEmpty) valueRow('الهاتف', 'Phone', customerPhone),
              if (customerAddress.isNotEmpty) valueRow('العنوان', 'Address', customerAddress),
            ],
            divider(),
            ...List.generate(items.length, (index) {
              final item = items[index];
              final secondary = item.effectiveSecondaryName;
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.only(bottom: 5),
                decoration: pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: border, width: .45)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    if (secondary.isNotEmpty)
                      arText(secondary, size: is58 ? 8.7 : 9.7, bold: true),
                    pw.Text(
                      item.name,
                      style: style(is58 ? 7.1 : 8.1, bold: secondary.isEmpty),
                      textAlign: pw.TextAlign.right,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: bilingualLabel('الكمية', 'Qty', arSize: 7.2, enSize: 5.8),
                        ),
                        pw.Text(_q(item.qty), style: style(is58 ? 7 : 8, bold: true)),
                        pw.SizedBox(width: 7),
                        pw.Expanded(
                          child: bilingualLabel('السعر', 'Price', arSize: 7.2, enSize: 5.8),
                        ),
                        pw.Text(_m(item.price), style: style(is58 ? 7 : 8, bold: true)),
                      ],
                    ),
                    if (item.discountAmount > 0)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: valueRow('الخصم', 'Discount', _m(item.discountAmount)),
                      ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1),
                      child: valueRow('المبلغ', 'Amount', _m(item.total), strong: true),
                    ),
                  ],
                ),
              );
            }),
            valueRow('المجموع الفرعي', 'Subtotal', _m(subtotal)),
            if (discount > 0) valueRow('الخصم', 'Discount', '-${_m(discount)}'),
            if (tax > 0) valueRow('الضريبة', 'Tax', _m(tax)),
            if (delivery > 0) valueRow('التوصيل', 'Delivery', _m(delivery)),
            divider(),
            valueRow('الإجمالي', 'TOTAL', _m(grandTotal), strong: true),
            if (paid > 0) valueRow('المدفوع', 'Paid', _m(paid), strong: true),
            if (change > 0) valueRow('الباقي', 'Change', _m(change), strong: true),
            if (balanceDue > .004) valueRow('المتبقي', 'Balance Due', _m(balanceDue), strong: true),
            if (payments.isNotEmpty) ...[
              divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [bilingualLabel('تفاصيل الدفع', 'Payment Details', arSize: 9, enSize: 7)],
              ),
              pw.SizedBox(height: 3),
              ...payments.map((p) {
                final label = (p['label'] ?? p['method'] ?? 'Payment').toString();
                final method = (p['method'] ?? label).toString();
                final raw = p['amount'];
                final amount = raw is num
                    ? raw.toDouble()
                    : double.tryParse((raw ?? '').toString()) ?? 0;
                final ref = (p['reference'] ?? '').toString().trim();
                final shown = ref.isEmpty ? _m(amount) : '${_m(amount)}  ($ref)';
                return valueRow(_arabicPaymentLabel(method), label, shown);
              }),
            ],
            if (showQr && _validQrUrl(qrUrl)) ...[
              divider(),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrUrl!.trim(),
                  width: is58 ? 52 : 64,
                  height: is58 ? 52 : 64,
                ),
              ),
              pw.SizedBox(height: 3),
              arText('امسح للمراجعة', size: is58 ? 7 : 8, bold: true, color: accent, align: pw.TextAlign.center),
              if (qrCaption.trim().isNotEmpty)
                _configuredPdfText(
                  qrCaption.trim(),
                  fonts: fonts,
                  arabicFirst: true,
                  fontSize: is58 ? 6 : 7,
                  color: muted,
                  align: pw.TextAlign.center,
                  lineGap: .6,
                ),
            ],
            if (activeFooterLines.isNotEmpty) ...[
              divider(),
              ...activeFooterLines.map(
                (line) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: _configuredPdfText(
                    line.trim(),
                    fonts: fonts,
                    arabicFirst: true,
                    fontSize: is58 ? 6.4 : 7.3,
                    align: pw.TextAlign.center,
                    lineGap: .6,
                  ),
                ),
              ),
            ],
            pw.SizedBox(height: 5),
            arText('شكراً لتسوقكم معنا', size: is58 ? 8 : 9, bold: true, color: accent, align: pw.TextAlign.center),
            pw.Text(
              'Thank you for your business!',
              style: style(is58 ? 6.4 : 7.2, bold: true, color: accent),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _buildArabicStandardInvoicePdf({
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
    final fonts = await _loadArabicFonts();
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
    final customerName = _customerDisplayName(customer);
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
      return sum +
          (raw is num
              ? raw.toDouble()
              : double.tryParse((raw ?? '').toString()) ?? 0);
    });
    final paid = paidFromPayments > 0 ? paidFromPayments : cashReceived;
    final balanceDue = (grandTotal - paid).clamp(0, double.infinity).toDouble();

    String dateOnly(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    String timeOnly(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    pw.TextStyle style(
      double size, {
      bool bold = false,
      PdfColor? color,
    }) =>
        pw.TextStyle(
          font: bold ? fonts.bold : fonts.regular,
          fontSize: size,
          color: color ?? ink,
        );

    pw.Widget arText(
      String text, {
      double size = 9,
      bool bold = true,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.right,
    }) =>
        pw.Text(
          text,
          style: style(size, bold: bold, color: color),
          textDirection: pw.TextDirection.rtl,
          textAlign: align,
        );

    pw.Widget bilingualLabel(
      String ar,
      String en, {
      double? width,
      bool strong = false,
    }) {
      final child = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          arText(ar, size: isA5 ? 7.7 : 8.7, bold: true),
          pw.Text(
            en,
            style: style(isA5 ? 5.7 : 6.5, bold: strong, color: muted),
            textAlign: pw.TextAlign.right,
          ),
        ],
      );
      return width == null ? child : pw.SizedBox(width: width, child: child);
    }

    pw.Widget singleValueRow(
      String ar,
      String en,
      String value, {
      bool strong = false,
      bool accentValue = false,
    }) =>
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: isA5 ? 2.2 : 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: _configuredPdfText(
                  value,
                  fonts: fonts,
                  arabicFirst: true,
                  fontSize: isA5 ? 7.5 : 8.8,
                  bold: strong || accentValue,
                  color: accentValue ? accent : ink,
                  align: pw.TextAlign.left,
                  lineGap: .7,
                ),
              ),
              pw.SizedBox(width: isA5 ? 7 : 10),
              bilingualLabel(ar, en, width: isA5 ? 80 : 105, strong: strong),
            ],
          ),
        );

    pw.Widget tableHeader(String ar, String en) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 2 : 4, vertical: isA5 ? 4 : 5),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              arText(ar, size: isA5 ? 6.4 : 7.2, bold: true, color: PdfColors.white, align: pw.TextAlign.center),
              pw.Text(
                en,
                style: style(isA5 ? 5.1 : 5.8, bold: true, color: PdfColors.white),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        );

    pw.Widget tableValue(
      String value, {
      pw.TextAlign align = pw.TextAlign.center,
      bool bold = false,
    }) =>
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 2 : 4, vertical: isA5 ? 5 : 6),
          child: pw.Text(
            value,
            style: style(isA5 ? 6.4 : 7.6, bold: bold),
            textAlign: align,
          ),
        );

    pw.Widget productCell(ReceiptItem item) {
      final secondary = item.effectiveSecondaryName;
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: isA5 ? 3 : 5, vertical: isA5 ? 4 : 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (secondary.isNotEmpty) ...[
              arText(secondary, size: isA5 ? 7 : 8.2, bold: true),
              pw.SizedBox(height: 1),
            ],
            pw.Text(
              item.name,
              style: style(isA5 ? 6.2 : 7.2, bold: secondary.isEmpty, color: secondary.isEmpty ? ink : muted),
              textAlign: pw.TextAlign.right,
            ),
          ],
        ),
      );
    }

    final configuredHeading =
        invoiceHeading.trim().isEmpty ? 'SALES INVOICE' : invoiceHeading.trim();
    final headingEn =
        _configuredLanguagePart(configuredHeading, arabic: false) ??
        'SALES INVOICE';
    final headingAr =
        _configuredLanguagePart(configuredHeading, arabic: true) ??
        _arabicInvoiceHeading(headingEn);
    final activeFooterLines = footerLines.where((line) => line.trim().isNotEmpty).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: pw.EdgeInsets.fromLTRB(isA5 ? 18 : 26, isA5 ? 18 : 24, isA5 ? 18 : 26, isA5 ? 20 : 26),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: border, width: .5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  arText('شكراً لتسوقكم معنا', size: isA5 ? 6.2 : 7, bold: true, color: accent),
                  pw.Text('Thank you for your business!', style: style(isA5 ? 5.3 : 6.1, color: accent)),
                ],
              ),
              pw.Text(
                'صفحة / Page ${context.pageNumber}/${context.pagesCount}',
                style: style(isA5 ? 5.5 : 6.3, color: muted),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (logoBytes != null) ...[
                pw.Center(
                  child: pw.SizedBox(
                    height: isA5 ? 42 : 52,
                    child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                  ),
                ),
                pw.SizedBox(height: 4),
              ],
              _configuredPdfText(
                shopName,
                fonts: fonts,
                arabicFirst: true,
                fontSize: isA5 ? 13 : 16,
                bold: true,
                color: accent,
                align: pw.TextAlign.center,
                lineGap: 1.4,
              ),
              if ((shopAddress ?? '').trim().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: _configuredPdfText(
                    shopAddress!.trim(),
                    fonts: fonts,
                    arabicFirst: true,
                    fontSize: isA5 ? 6.4 : 7.4,
                    color: muted,
                    align: pw.TextAlign.center,
                    lineGap: .8,
                  ),
                ),
              if ((shopPhone ?? '').trim().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 1),
                  child: pw.Text(shopPhone!.trim(), style: style(isA5 ? 6.4 : 7.4, color: muted), textAlign: pw.TextAlign.center),
                ),
              pw.SizedBox(height: isA5 ? 6 : 8),
              arText(headingAr, size: isA5 ? 14 : 17, bold: true, color: accent, align: pw.TextAlign.center),
              pw.Text(
                headingEn,
                style: style(isA5 ? 8.5 : 10, bold: true, color: accent),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
          pw.SizedBox(height: isA5 ? 8 : 11),
          pw.Container(
            padding: pw.EdgeInsets.all(isA5 ? 7 : 9),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
              border: pw.Border.all(color: border, width: .7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                singleValueRow('رقم الفاتورة', 'Invoice No.', receiptNo, strong: true),
                singleValueRow('التاريخ', 'Date', dateOnly(dateTime)),
                singleValueRow('الوقت', 'Time', timeOnly(dateTime)),
                if (receiptNo.startsWith('OFF-'))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Column(
                      children: [
                        arText('غير متصل - بانتظار المزامنة', size: isA5 ? 6.2 : 7, bold: true, color: accent, align: pw.TextAlign.center),
                        pw.Text('Offline - Pending Sync', style: style(isA5 ? 5.3 : 6.1, color: muted), textAlign: pw.TextAlign.center),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: isA5 ? 7 : 10),
          pw.Container(
            padding: pw.EdgeInsets.all(isA5 ? 7 : 9),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
              border: pw.Border.all(color: border, width: .7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                singleValueRow('العميل', 'Customer', effectiveCustomer, strong: true),
                if (customerPhone.isNotEmpty) singleValueRow('الهاتف', 'Phone', customerPhone),
                if (customerAddress.isNotEmpty) singleValueRow('العنوان', 'Address', customerAddress),
              ],
            ),
          ),
          pw.SizedBox(height: isA5 ? 8 : 11),
          pw.Table(
            border: pw.TableBorder(
              verticalInside: pw.BorderSide(color: border, width: .35),
              horizontalInside: pw.BorderSide(color: border, width: .35),
              bottom: pw.BorderSide(color: border, width: .6),
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(20),
              1: const pw.FlexColumnWidth(3.9),
              2: const pw.FlexColumnWidth(1.05),
              3: const pw.FlexColumnWidth(.85),
              4: const pw.FlexColumnWidth(1.45),
              5: const pw.FlexColumnWidth(1.25),
              6: const pw.FlexColumnWidth(1.45),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: accent),
                children: [
                  tableHeader('#', '#'),
                  tableHeader('المنتج', 'Product'),
                  tableHeader('الوحدة', 'Unit'),
                  tableHeader('الكمية', 'Qty'),
                  tableHeader('سعر الوحدة', 'Unit Price'),
                  tableHeader('الخصم', 'Discount'),
                  tableHeader('المبلغ', 'Amount'),
                ],
              ),
              ...List.generate(items.length, (index) {
                final item = items[index];
                return pw.TableRow(
                  children: [
                    tableValue('${index + 1}'),
                    productCell(item),
                    tableValue(item.unitName.isEmpty ? '-' : item.unitName),
                    tableValue(_q(item.qty)),
                    tableValue(_m(item.price), align: pw.TextAlign.right),
                    tableValue(_m(item.discountAmount), align: pw.TextAlign.right),
                    tableValue(_m(item.total), align: pw.TextAlign.right, bold: true),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: isA5 ? 8 : 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: pw.EdgeInsets.all(isA5 ? 7 : 9),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: border, width: .6),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      bilingualLabel('تفاصيل الدفع', 'Payment Details'),
                      pw.SizedBox(height: 4),
                      if (payments.isEmpty)
                        pw.Text('-', style: style(isA5 ? 6 : 7, color: muted))
                      else
                        ...payments.map((p) {
                          final label = (p['label'] ?? p['method'] ?? 'Payment').toString();
                          final method = (p['method'] ?? label).toString();
                          final raw = p['amount'];
                          final amount = raw is num
                              ? raw.toDouble()
                              : double.tryParse((raw ?? '').toString()) ?? 0;
                          final ref = (p['reference'] ?? '').toString().trim();
                          return pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 3),
                            child: singleValueRow(
                              _arabicPaymentLabel(method),
                              label,
                              ref.isEmpty ? _m(amount) : '${_m(amount)}  ($ref)',
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: isA5 ? 8 : 12),
              pw.Expanded(
                child: pw.Container(
                  padding: pw.EdgeInsets.all(isA5 ? 7 : 9),
                  decoration: pw.BoxDecoration(
                    color: accentSoft,
                    border: pw.Border.all(color: border, width: .6),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    children: [
                      singleValueRow('المجموع الفرعي', 'Subtotal', _m(subtotal)),
                      if (discount > 0) singleValueRow('الخصم', 'Discount', '-${_m(discount)}'),
                      if (tax > 0) singleValueRow('الضريبة', 'Tax', _m(tax)),
                      if (delivery > 0) singleValueRow('التوصيل', 'Delivery', _m(delivery)),
                      pw.Container(height: .6, margin: const pw.EdgeInsets.symmetric(vertical: 4), color: border),
                      singleValueRow('الإجمالي', 'TOTAL', _m(grandTotal), strong: true, accentValue: true),
                      if (paid > 0) singleValueRow('المدفوع', 'Paid', _m(paid), strong: true),
                      if (change > 0) singleValueRow('الباقي', 'Change', _m(change), strong: true),
                      if (balanceDue > .004) singleValueRow('المتبقي', 'Balance Due', _m(balanceDue), strong: true, accentValue: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: isA5 ? 8 : 12),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(isA5 ? 7 : 9),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: border, width: .6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (showQr && _validQrUrl(qrUrl)) ...[
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrUrl!.trim(),
                    width: isA5 ? 48 : 58,
                    height: isA5 ? 48 : 58,
                  ),
                  pw.SizedBox(width: isA5 ? 7 : 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      arText('امسح للمراجعة', size: isA5 ? 6.6 : 7.6, bold: true, color: accent),
                      if (qrCaption.trim().isNotEmpty)
                        _configuredPdfText(
                          qrCaption.trim(),
                          fonts: fonts,
                          arabicFirst: true,
                          fontSize: isA5 ? 5.6 : 6.5,
                          color: muted,
                          align: pw.TextAlign.left,
                          lineGap: .6,
                        ),
                    ],
                  ),
                ],
                pw.Spacer(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    arText('شكراً لتسوقكم معنا', size: isA5 ? 7.4 : 8.6, bold: true, color: accent, align: pw.TextAlign.center),
                    pw.Text('Thank you for your business!', style: style(isA5 ? 5.8 : 6.8, bold: true, color: accent), textAlign: pw.TextAlign.center),
                  ],
                ),
                if (activeFooterLines.isNotEmpty) ...[
                  pw.Spacer(),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: activeFooterLines
                        .map((line) => pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 2),
                              child: _configuredPdfText(
                                line.trim(),
                                fonts: fonts,
                                arabicFirst: true,
                                fontSize: isA5 ? 5.5 : 6.4,
                                color: muted,
                                align: pw.TextAlign.right,
                                lineGap: .5,
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 10),
        ],
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
    final customerName = _customerDisplayName(customer);
    final customerPhone = (customer['phone'] ?? '').toString().trim();
    final customerAddress = (customer['address'] ?? '').toString().trim();
    final effectiveCustomer = customerName.isEmpty ? 'Walk-in Customer' : customerName;

    final brandingNeedsArabic = <String>[
      shopName,
      shopAddress ?? '',
      invoiceHeading,
      qrCaption,
      ...footerLines,
    ].any(_containsArabic);
    final ArabicPdfFonts? brandingFonts =
        brandingNeedsArabic ? await _loadArabicFonts() : null;

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

    pw.Widget brandedText(
      String value, {
      required double size,
      bool bold = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      if (brandingFonts != null && _containsArabic(value)) {
        return _configuredPdfText(
          value,
          fonts: brandingFonts,
          arabicFirst: false,
          fontSize: size,
          bold: bold,
          color: color ?? ink,
          align: align,
          lineGap: .8,
        );
      }
      return pw.Text(
        value,
        style: textStyle(size, bold: bold, color: color),
        textAlign: align,
      );
    }

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
                    brandedText(
                      shopName,
                      size: isA5 ? 15 : 18,
                      bold: true,
                      align: pw.TextAlign.left,
                    ),
                    if ((shopAddress ?? '').trim().isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      brandedText(
                        shopAddress!.trim(),
                        size: isA5 ? 7.5 : 8.5,
                        color: muted,
                        align: pw.TextAlign.left,
                      ),
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
                    brandedText(
                      heading,
                      size: isA5 ? 11 : 13,
                      bold: true,
                      color: accent,
                      align: pw.TextAlign.right,
                    ),
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
                            child: brandedText(
                              line.trim(),
                              size: isA5 ? 7.5 : 8.5,
                              color: muted,
                              align: pw.TextAlign.left,
                            ),
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
                            pw.Expanded(
                              child: brandedText(
                                qrCaption.trim(),
                                size: isA5 ? 7.5 : 8.5,
                                bold: true,
                                color: accent,
                                align: pw.TextAlign.left,
                              ),
                            ),
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
