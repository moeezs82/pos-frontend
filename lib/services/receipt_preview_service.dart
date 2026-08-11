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
    final base = paperWidth == 'mm58' ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    return base.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
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
        : const [];

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

  static String _m(num v) => v.toStringAsFixed(2);
  static String _q(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toString();
}
