import 'dart:typed_data';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

class ThermalPrinterService {
  ThermalPrinterService._();
  static final instance = ThermalPrinterService._();

  final PaperSize paperSize = PaperSize.mm80;

  // ✅ Default logo like preview
  static const String defaultLogoAsset = "assets/images/receipt_logo.png";

  Future<void> printSaleReceipt({
    required String printerIp,
    int port = 9100,
    required String shopName,
    String? shopAddress,
    String? shopPhone,

    // ✅ logo support (same idea as preview)
    String? logoAsset,
    Uint8List? logoBytes,

    required String receiptNo,
    required DateTime dateTime,
    required List<ReceiptItem> items,
    required double subtotal,
    required double discount,
    required double tax,
    required double grandTotal,
    // required double cashReceived,
    // required double changeAmount,
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

    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paperSize, profile);

    final res = await printer.connect(printerIp, port: port);
    if (res != PosPrintResult.success) {
      throw Exception("Printer connect failed: ${res.msg}");
    }

    // ✅ PRINT LOGO (like preview)
    await _printLogo(
      printer,
      logoBytes: logoBytes,
      logoAsset: logoAsset,
    );

    // ---- Header ----
    printer.text(
      shopName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1,
    );

    if (shopAddress != null && shopAddress.trim().isNotEmpty) {
      printer.text(shopAddress, styles: const PosStyles(align: PosAlign.center));
    }
    if (shopPhone != null && shopPhone.trim().isNotEmpty) {
      printer.text(shopPhone, styles: const PosStyles(align: PosAlign.center));
    }

    printer.hr();

    printer.text(
      "Receipt# $receiptNo",
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );

    final d = _formatDateTime(dateTime);
    printer.text(
      "Date : $d",
      styles: const PosStyles(align: PosAlign.center),
      linesAfter: 1,
    );

    printer.hr();

    // ---- Customer block (from meta) ----
    final hasCustomerInfo =
        cName.isNotEmpty || cPhone.isNotEmpty || cAddr.isNotEmpty;

    if (hasCustomerInfo) {
      printer.text("Customer", styles: const PosStyles(bold: true));
      if (cName.isNotEmpty) printer.text("Name: $cName");
      if (cPhone.isNotEmpty) printer.text("Phone: $cPhone");
      if (cAddr.isNotEmpty) printer.text("Address: $cAddr");
      printer.hr();
    }

    // ---- Items table ----
    printer.row([
      PosColumn(text: "Name", width: 5, styles: const PosStyles(bold: true)),
      PosColumn(
        text: "Price",
        width: 2,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
      PosColumn(
        text: "Qty",
        width: 2,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
      PosColumn(
        text: "Total",
        width: 3,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);

    printer.hr();

    for (final it in items) {
      printer.text(it.name, styles: const PosStyles(bold: true));
      printer.row([
        PosColumn(text: "", width: 5),
        PosColumn(
          text: _money(it.price),
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: _qty(it.qty),
          width: 2,
          styles: const PosStyles(align: PosAlign.right),
        ),
        PosColumn(
          text: _money(it.total),
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      printer.feed(1);
    }

    printer.hr();

    // ---- Totals ----
    _kv(printer, "Subtotal", _money(subtotal), boldRight: true);
    if (discount > 0) _kv(printer, "Discount", "-${_money(discount)}", boldRight: true);
    if (tax > 0) _kv(printer, "Tax", _money(tax), boldRight: true);
    if (delivery > 0) _kv(printer, "Delivery", _money(delivery), boldRight: true);

    printer.hr();

    _kv(
      printer,
      "Grand Total",
      _money(grandTotal),
      boldLeft: true,
      boldRight: true,
      rightBig: true,
    );

    printer.feed(1);

    // _kv(printer, "Cash Received", _money(cashReceived), boldRight: true);
    // _kv(printer, "Change Amount", _money(changeAmount), boldRight: true);

    printer.hr();

    // ✅ Footer same as preview
    printer.text(
      "Thank You, Order Again.",
      styles: const PosStyles(align: PosAlign.center, bold: true),
      linesAfter: 1,
    );
    printer.text(
      "Powered By FriendDevelopers",
      styles: const PosStyles(align: PosAlign.center),
    );
    printer.text(
      "03033807582",
      styles: const PosStyles(align: PosAlign.center),
    );

    printer.feed(2);
    printer.cut();
    printer.disconnect();
  }

  /// ✅ Print logo from bytes or asset (default)
  Future<void> _printLogo(
    NetworkPrinter printer, {
    Uint8List? logoBytes,
    String? logoAsset,
  }) async {
    Uint8List? bytes = logoBytes;

    final String effectiveAsset =
        (logoAsset != null && logoAsset.trim().isNotEmpty)
            ? logoAsset
            : defaultLogoAsset;

    if (bytes == null) {
      try {
        final bd = await rootBundle.load(effectiveAsset);
        bytes = bd.buffer.asUint8List();
      } catch (_) {
        bytes = null;
      }
    }

    if (bytes == null) return;

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      // ✅ make it printer-friendly: grayscale + resize
      final resized = img.copyResize(decoded, width: 220); // good for 80mm
      final raster = img.grayscale(resized);

      printer.imageRaster(raster, align: PosAlign.center);
      printer.feed(1);
    } catch (_) {
      // ignore image print failure
    }
  }

  static void _kv(
    NetworkPrinter printer,
    String left,
    String right, {
    bool boldLeft = false,
    bool boldRight = false,
    bool rightBig = false,
  }) {
    printer.row([
      PosColumn(text: left, width: 8, styles: PosStyles(bold: boldLeft)),
      PosColumn(
        text: right,
        width: 4,
        styles: PosStyles(
          align: PosAlign.right,
          bold: boldRight,
          height: rightBig ? PosTextSize.size2 : PosTextSize.size1,
          width: rightBig ? PosTextSize.size2 : PosTextSize.size1,
        ),
      ),
    ]);
  }

  static String _formatDateTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final mm = dt.minute.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = _monthShort(dt.month);
    return "$dd $mo ${dt.year} - $h:$mm $ampm";
  }

  static String _monthShort(int m) {
    const months = [
      "Jan","Feb","Mar","Apr","May","Jun",
      "Jul","Aug","Sep","Oct","Nov","Dec"
    ];
    return months[(m - 1).clamp(0, 11)];
  }

  static String _money(num v) => v.toStringAsFixed(2);
  static String _qty(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toString();
}

class ReceiptItem {
  final String name;
  final double price;
  final double qty;
  final double total;

  ReceiptItem({
    required this.name,
    required this.price,
    required this.qty,
    required this.total,
  });
}
