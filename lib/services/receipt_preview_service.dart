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
    );

    if (layoutForPrinting) {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
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

    final doc = pw.Document();
    final pageFormat = paperWidth == 'mm58' ? PdfPageFormat.roll57 : PdfPageFormat.roll80;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
          const pw.TextStyle normal = pw.TextStyle(fontSize: 9);
          const pw.TextStyle small = pw.TextStyle(fontSize: 8);

          final String dt =
              "${dateTime.day.toString().padLeft(2, '0')}/"
              "${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} "
              "${dateTime.hour.toString().padLeft(2, '0')}:"
              "${dateTime.minute.toString().padLeft(2, '0')}";

          pw.Widget kv(String k, String v, {bool bold2 = false}) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(k, style: bold2 ? bold : normal),
              pw.Text(v, style: bold2 ? bold : normal),
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
              if (sections.header) ...[
                pw.Center(child: pw.Text(shopName, style: shopStyle)),
                if (shopAddress != null && shopAddress.trim().isNotEmpty)
                  pw.Center(child: pw.Text(shopAddress, style: small)),
                if (shopPhone != null && shopPhone.trim().isNotEmpty)
                  pw.Center(child: pw.Text(shopPhone, style: small)),
                divider(),
              ] else
                pw.Center(child: pw.Text(shopName, style: bold)),

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

              // ── ITEMS HEADER ───────────────────────────────────────────────
              pw.Row(
                children: [
                  pw.Expanded(flex: 5, child: pw.Text("Item", style: bold)),
                  if (sections.totalsBreakdown)
                    pw.Expanded(
                      flex: 2,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text("Price", style: bold),
                      ),
                    ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text("Qty", style: bold),
                    ),
                  ),
                  if (sections.totalsBreakdown)
                    pw.Expanded(
                      flex: 2,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text("Total", style: bold),
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 3),

              // ── ITEMS ──────────────────────────────────────────────────────
              ...items.map((it) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  children: [
                    pw.Expanded(flex: 5, child: pw.Text(it.name, style: normal)),
                    if (sections.totalsBreakdown)
                      pw.Expanded(
                        flex: 2,
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(_m(it.price), style: normal),
                        ),
                      ),
                    pw.Expanded(
                      flex: 1,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(_q(it.qty), style: normal),
                      ),
                    ),
                    if (sections.totalsBreakdown)
                      pw.Expanded(
                        flex: 2,
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(_m(it.total), style: normal),
                        ),
                      ),
                  ],
                ),
              )),

              dashedDivider(),

              // ── TOTALS ─────────────────────────────────────────────────────
              if (sections.totalsBreakdown) ...[
                kv("Subtotal", _m(subtotal), bold2: false),
                if (discount > 0) kv("Discount", "-${_m(discount)}"),
                if (tax > 0) kv("Tax", _m(tax)),
                if (delivery > 0) kv("Delivery", _m(delivery)),
                divider(),
              ],

              // Grand total always shows.
              kv("Grand Total", _m(grandTotal), bold2: true),
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
