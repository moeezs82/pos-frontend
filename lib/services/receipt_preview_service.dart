import 'dart:typed_data';
import 'package:enterprise_pos/services/thermal_printer_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReceiptPreviewService {
  ReceiptPreviewService._();
  static final instance = ReceiptPreviewService._();

  // ✅ Default logo (make sure this asset exists in pubspec.yaml)
  static const String defaultLogoAsset = "assets/images/receipt_logo.png";

  Future<void> previewReceipt({
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    String? logoAsset, // ✅ add this (asset path)
    Uint8List? logoBytes, // ✅ or pass bytes directly
    required String receiptNo,
    required DateTime dateTime,
    required List<ReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    Map<String, dynamic>? meta,
  }) async {
    // --- extract meta safely ---
    final snapRaw = meta?["customer_snapshot"];
    final snap = (snapRaw is Map)
        ? snapRaw.cast<String, dynamic>()
        : <String, dynamic>{};

    final cName = (snap["name"] ?? "").toString().trim();
    final cPhone = (snap["phone"] ?? "").toString().trim();
    final cAddr = (snap["address"] ?? "").toString().trim();

    final delivery = (meta?["delivery"] is num)
        ? (meta!["delivery"] as num).toDouble()
        : double.tryParse((meta?["delivery"] ?? "").toString()) ?? 0.0;

    // ✅ Resolve logo asset: use provided OR default
    final String effectiveLogoAsset =
        (logoAsset != null && logoAsset.trim().isNotEmpty)
        ? logoAsset
        : defaultLogoAsset;

    // --- load logo bytes (if asset provided) ---
    Uint8List? resolvedLogoBytes = logoBytes;
    if (resolvedLogoBytes == null) {
      try {
        final bd = await rootBundle.load(effectiveLogoAsset);
        resolvedLogoBytes = bd.buffer.asUint8List();
      } catch (_) {
        resolvedLogoBytes = null; // ignore if missing
      }
    }

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        build: (_) {
          pw.Widget line() => pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            height: 1,
            color: PdfColors.grey300,
          );

          final pw.TextStyle h1 = pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          );
          final pw.TextStyle b = pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          );
          const pw.TextStyle n = pw.TextStyle(fontSize: 10);

          final String dt =
              "${dateTime.day.toString().padLeft(2, '0')}/"
              "${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} "
              "${dateTime.hour.toString().padLeft(2, '0')}:"
              "${dateTime.minute.toString().padLeft(2, '0')}";

          pw.Widget kv(String k, String v, {bool bold = false}) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(k, style: bold ? b : n),
              pw.Text(v, style: bold ? b : n),
            ],
          );

          final bool hasCustomerInfo =
              cName.isNotEmpty || cPhone.isNotEmpty || cAddr.isNotEmpty;

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ✅ LOGO TOP
              if (resolvedLogoBytes != null) ...[
                pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(resolvedLogoBytes),
                    width: 110, // adjust size as you like
                    height: 110,
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(height: 6),
              ],

              pw.Center(child: pw.Text(shopName, style: h1)),
              if (shopAddress != null && shopAddress.trim().isNotEmpty)
                pw.Center(child: pw.Text(shopAddress, style: n)),
              if (shopPhone != null && shopPhone.trim().isNotEmpty)
                pw.Center(child: pw.Text(shopPhone, style: n)),

              line(),

              pw.Center(child: pw.Text("Receipt# $receiptNo", style: b)),
              pw.Center(child: pw.Text("Date : $dt", style: n)),

              line(),

              if (hasCustomerInfo) ...[
                pw.Text("Customer", style: b),
                if (cName.isNotEmpty) pw.Text("Name: $cName", style: n),
                if (cPhone.isNotEmpty) pw.Text("Phone: $cPhone", style: n),
                if (cAddr.isNotEmpty) pw.Text("Address: $cAddr", style: n),
                line(),
              ],

              pw.Row(
                children: [
                  pw.Expanded(flex: 5, child: pw.Text("Name", style: b)),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text("Price", style: b),
                    ),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text("Qty", style: b),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text("Total", style: b),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),

              ...items.map((it) {
                return pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(flex: 5, child: pw.Text(it.name, style: n)),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(_m(it.price), style: n),
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(_q(it.qty), style: n),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Text(_m(it.total), style: n),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                  ],
                );
              }).toList(),

              line(),

              kv("Subtotal", _m(subtotal), bold: true),
              if (discount > 0) kv("Discount", "-${_m(discount)}", bold: true),
              if (tax > 0) kv("Tax", _m(tax), bold: true),
              if (delivery > 0) kv("Delivery", _m(delivery), bold: true),

              line(),

              kv("Grand Total", _m(grandTotal), bold: true),
              pw.SizedBox(height: 6),
              // kv("Cash Received", _m(cashReceived), bold: true),
              // kv("Change Amount", _m(changeAmount), bold: true),

              line(),

              pw.Center(child: pw.Text("Thank You, Order Again.", style: b)),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text("Powered By FriendDevelopers", style: n)),
              pw.Center(child: pw.Text("03033807582", style: n)),
            ],
          );
        },
      ),
    );

    final Uint8List bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static String _m(num v) => v.toStringAsFixed(2);
  static String _q(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toString();
}
