import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enterprise_pos/models/printer_config.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BarcodeLabelPrinterService {
  BarcodeLabelPrinterService._();
  static final instance = BarcodeLabelPrinterService._();

  static const int maxCopies = 1000;

  PdfPageFormat pageFormat(PrinterConfig config) {
    final landscape = config.barcodeOrientation == 'landscape';
    final widthMm = landscape ? config.barcodeLabelHeightMm : config.barcodeLabelWidthMm;
    final heightMm = landscape ? config.barcodeLabelWidthMm : config.barcodeLabelHeightMm;
    return PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
  }

  Future<Uint8List> buildLabelsPdf({
    required PrinterConfig config,
    required String productName,
    required String barcode,
    required double price,
    int copies = 1,
  }) async {
    _validate(config: config, barcode: barcode, copies: copies);

    final doc = pw.Document();
    final format = pageFormat(config);
    final safeName = _printableAscii(productName, maxLength: 80);
    final safeBarcode = _singleLine(barcode, maxLength: 100);
    final currency = _printableAscii(config.barcodeCurrency, maxLength: 20);
    final priceText = _priceText(price, currency);

    for (var i = 0; i < copies; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.all(1.5 * PdfPageFormat.mm),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (config.barcodeShowName)
                pw.SizedBox(
                  height: 4.5 * PdfPageFormat.mm,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    child: pw.Text(
                      safeName.isEmpty ? 'Product' : safeName,
                      maxLines: 1,
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),
              pw.SizedBox(height: .8 * PdfPageFormat.mm),
              pw.Expanded(
                child: pw.Padding(
                  padding: pw.EdgeInsets.symmetric(horizontal: 1.5 * PdfPageFormat.mm),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: safeBarcode,
                    drawText: false,
                  ),
                ),
              ),
              if (config.barcodeShowValue) ...[
                pw.SizedBox(height: .6 * PdfPageFormat.mm),
                pw.SizedBox(
                  height: 3.2 * PdfPageFormat.mm,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    child: pw.Text(safeBarcode, style: const pw.TextStyle(fontSize: 7)),
                  ),
                ),
              ],
              if (config.barcodeShowPrice) ...[
                pw.SizedBox(height: .5 * PdfPageFormat.mm),
                pw.SizedBox(
                  height: 4.5 * PdfPageFormat.mm,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    child: pw.Text(
                      priceText,
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  Future<void> printLabels({
    required PrinterConfig config,
    required String productName,
    required String barcode,
    required double price,
    required int copies,
  }) async {
    _validate(config: config, barcode: barcode, copies: copies);

    if (config.barcodeConnection == 'network') {
      await _printRawNetwork(
        config: config,
        productName: productName,
        barcode: barcode,
        price: price,
        copies: copies,
      );
      return;
    }

    final bytes = await buildLabelsPdf(
      config: config,
      productName: productName,
      barcode: barcode,
      price: price,
      copies: copies,
    );

    if (config.barcodeConnection == 'local' &&
        (config.barcodeLocalPrinterName ?? '').trim().isNotEmpty) {
      try {
        final wanted = config.barcodeLocalPrinterName!.trim().toLowerCase();
        final printers = await Printing.listPrinters();
        Printer? selected;
        for (final printer in printers) {
          if (printer.name.trim().toLowerCase() == wanted) {
            selected = printer;
            break;
          }
        }

        if (selected != null) {
          final printed = await Printing.directPrintPdf(
            printer: selected,
            name: 'Barcode - ${_singleLine(productName, maxLength: 40)}',
            format: pageFormat(config),
            dynamicLayout: false,
            onLayout: (_) async => bytes,
          );
          if (printed) return;
        }
      } catch (_) {
        // Driver enumeration/direct-print support varies by platform. The
        // system dialog below is the universal recovery path.
      }
    }

    // Universal fallback: let the operating system/installed driver select
    // and calibrate the physical printer while preserving the label page size.
    await Printing.layoutPdf(
      name: 'Barcode - ${_singleLine(productName, maxLength: 40)}',
      format: pageFormat(config),
      dynamicLayout: false,
      onLayout: (_) async => bytes,
    );
  }

  Future<void> testPrint(PrinterConfig config) {
    return printLabels(
      config: config.copyWith(barcodePrintEnabled: true),
      productName: 'Barcode Printer Test',
      barcode: '123456789012',
      price: 9.99,
      copies: 1,
    );
  }

  Future<void> _printRawNetwork({
    required PrinterConfig config,
    required String productName,
    required String barcode,
    required double price,
    required int copies,
  }) async {
    final ip = (config.barcodeNetworkIp ?? '').trim();
    if (ip.isEmpty) throw Exception('Barcode printer network address is missing.');

    final language = config.barcodePrinterLanguage.toLowerCase();
    final command = switch (language) {
      'zpl' => _zpl(config, productName, barcode, price, copies),
      'tspl' => _tspl(config, productName, barcode, price, copies),
      _ => throw Exception('Direct network printing requires a ZPL or TSPL printer profile.'),
    };

    final socket = await Socket.connect(
      ip,
      config.barcodeNetworkPort,
      timeout: const Duration(seconds: 7),
    );
    try {
      socket.add(utf8.encode(command));
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  String _zpl(PrinterConfig c, String name, String barcode, double price, int copies) {
    final size = _dotSize(c);
    final width = size.$1;
    final height = size.$2;
    final margin = _mmToDots(2, c.barcodeDpi);
    final contentWidth = width - (margin * 2);
    final nameY = _mmToDots(1, c.barcodeDpi);
    final barcodeY = _mmToDots(6, c.barcodeDpi);
    final barcodeHeight = _mmToDots((height / c.barcodeDpi * 25.4 * .35).clamp(7, 14), c.barcodeDpi);
    final valueY = (barcodeY + barcodeHeight + _mmToDots(1, c.barcodeDpi)).clamp(0, height - margin);
    final priceY = (height - _mmToDots(5, c.barcodeDpi)).clamp(0, height - margin);
    final module = (c.barcodeDpi / 203).round().clamp(1, 3);
    final currency = c.barcodeCurrency.trim();
    final priceText = _priceText(price, currency);
    final b = StringBuffer('^XA\n^PW$width\n^LL$height\n^LH0,0\n');
    if (c.barcodeShowName) {
      b.writeln('^FO$margin,$nameY^A0N,${_mmToDots(3, c.barcodeDpi)},${_mmToDots(3, c.barcodeDpi)}^FB$contentWidth,1,0,C,0^FD${_zplText(name)}^FS');
    }
    b.writeln('^FO$margin,$barcodeY^BY$module,2,$barcodeHeight^BCN,$barcodeHeight,N,N,N^FD${_zplText(barcode)}^FS');
    if (c.barcodeShowValue) {
      b.writeln('^FO$margin,$valueY^A0N,${_mmToDots(2.5, c.barcodeDpi)},${_mmToDots(2.5, c.barcodeDpi)}^FB$contentWidth,1,0,C,0^FD${_zplText(barcode)}^FS');
    }
    if (c.barcodeShowPrice) {
      b.writeln('^FO$margin,$priceY^A0N,${_mmToDots(4, c.barcodeDpi)},${_mmToDots(4, c.barcodeDpi)}^FB$contentWidth,1,0,C,0^FD${_zplText(priceText)}^FS');
    }
    b.writeln('^PQ$copies,0,1,N\n^XZ');
    return b.toString();
  }

  String _tspl(PrinterConfig c, String name, String barcode, double price, int copies) {
    final landscape = c.barcodeOrientation == 'landscape';
    final widthMm = landscape ? c.barcodeLabelHeightMm : c.barcodeLabelWidthMm;
    final heightMm = landscape ? c.barcodeLabelWidthMm : c.barcodeLabelHeightMm;
    final size = _dotSize(c);
    final width = size.$1;
    final height = size.$2;
    final margin = _mmToDots(2, c.barcodeDpi);
    final barcodeY = _mmToDots(6, c.barcodeDpi);
    final barHeight = _mmToDots((heightMm * .35).clamp(7, 14), c.barcodeDpi);
    final currency = c.barcodeCurrency.trim();
    final priceText = _priceText(price, currency);
    final b = StringBuffer()
      ..writeln('SIZE ${widthMm.toStringAsFixed(2)} mm,${heightMm.toStringAsFixed(2)} mm')
      ..writeln('GAP ${c.barcodeLabelGapMm.toStringAsFixed(2)} mm,0 mm')
      ..writeln('DIRECTION 1')
      ..writeln('CLS');
    if (c.barcodeShowName) {
      b.writeln('TEXT ${_centerX(width, name, _mmToDots(2.5, c.barcodeDpi))},${_mmToDots(1, c.barcodeDpi)},"3",0,1,1,"${_tsplText(name)}"');
    }
    b.writeln('BARCODE $margin,$barcodeY,"128",$barHeight,0,0,2,2,"${_tsplText(barcode)}"');
    if (c.barcodeShowValue) {
      b.writeln('TEXT ${_centerX(width, barcode, _mmToDots(2, c.barcodeDpi))},${barcodeY + barHeight + _mmToDots(1, c.barcodeDpi)},"2",0,1,1,"${_tsplText(barcode)}"');
    }
    if (c.barcodeShowPrice) {
      b.writeln('TEXT ${_centerX(width, priceText, _mmToDots(3, c.barcodeDpi))},${(height - _mmToDots(5, c.barcodeDpi)).clamp(0, height - margin)},"4",0,1,1,"${_tsplText(priceText)}"');
    }
    b.writeln('PRINT 1,$copies');
    return b.toString();
  }

  (int, int) _dotSize(PrinterConfig config) {
    final landscape = config.barcodeOrientation == 'landscape';
    final widthMm = landscape ? config.barcodeLabelHeightMm : config.barcodeLabelWidthMm;
    final heightMm = landscape ? config.barcodeLabelWidthMm : config.barcodeLabelHeightMm;
    return (_mmToDots(widthMm, config.barcodeDpi), _mmToDots(heightMm, config.barcodeDpi));
  }

  int _mmToDots(num mm, int dpi) => (mm * dpi / 25.4).round();

  int _centerX(int width, String value, int charWidth) =>
      ((width - (_singleLine(value, maxLength: 80).length * charWidth * .55)) / 2)
          .round()
          .clamp(0, width)
          .toInt();

  String _singleLine(String value, {required int maxLength}) {
    final result = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return result.length <= maxLength ? result : result.substring(0, maxLength);
  }

  String _zplText(String value) =>
      _printableAscii(value, maxLength: 100).replaceAll('^', ' ').replaceAll('~', ' ');

  String _tsplText(String value) =>
      _printableAscii(value, maxLength: 100).replaceAll('"', "'");

  String _printableAscii(String value, {required int maxLength}) {
    final singleLine = _singleLine(value, maxLength: maxLength);
    return String.fromCharCodes(
      singleLine.codeUnits.map((unit) => unit >= 32 && unit <= 126 ? unit : 63),
    );
  }

  String _priceText(double price, String currency) {
    final amount = price.toStringAsFixed(2);
    if (currency.isEmpty) return amount;
    return const {r'$', '€', '£', '¥', '₹', '₩', '₽', '₺', '₫', '฿', '₱'}
            .contains(currency)
        ? '$currency$amount'
        : '$amount $currency';
  }

  void _validate({
    required PrinterConfig config,
    required String barcode,
    required int copies,
  }) {
    if (!config.barcodePrintEnabled) {
      throw Exception('Barcode printing is disabled for this branch.');
    }
    if (barcode.trim().isEmpty) throw Exception('This product does not have a barcode.');
    if (barcode.length > 100) throw Exception('The product barcode is too long to print.');
    if (barcode.codeUnits.any((unit) => unit < 32 || unit > 126)) {
      throw Exception('Barcode labels support printable ASCII characters only.');
    }
    if (copies < 1 || copies > maxCopies) {
      throw Exception('Label quantity must be between 1 and $maxCopies.');
    }
    if (config.barcodeLabelWidthMm < 15 || config.barcodeLabelHeightMm < 10) {
      throw Exception('The configured barcode label size is invalid.');
    }
    if (config.barcodeLabelWidthMm > 200 || config.barcodeLabelHeightMm > 200) {
      throw Exception('The configured barcode label size is too large.');
    }
    if (!const {203, 300, 600}.contains(config.barcodeDpi)) {
      throw Exception('The configured barcode printer resolution is invalid.');
    }
    if (!const {'dialog', 'local', 'network'}.contains(config.barcodeConnection)) {
      throw Exception('The configured barcode printer connection is invalid.');
    }
    if (config.barcodeConnection == 'network') {
      if ((config.barcodeNetworkIp ?? '').trim().isEmpty) {
        throw Exception('Barcode printer network address is missing.');
      }
      if (!const {'zpl', 'tspl'}.contains(config.barcodePrinterLanguage.toLowerCase())) {
        throw Exception('Direct network printing requires ZPL or TSPL.');
      }
    }
  }
}
