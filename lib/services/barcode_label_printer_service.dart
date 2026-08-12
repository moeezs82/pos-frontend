import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/services/local_printer_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BarcodeLabelItem {
  final String productName;
  final String variantDetails;
  final String barcode;
  final double price;
  final int copies;

  const BarcodeLabelItem({
    required this.productName,
    this.variantDetails = '',
    required this.barcode,
    required this.price,
    this.copies = 1,
  });

  BarcodeLabelItem copyWith({int? copies}) => BarcodeLabelItem(
        productName: productName,
        variantDetails: variantDetails,
        barcode: barcode,
        price: price,
        copies: copies ?? this.copies,
      );
}

/// Barcode output layout selected at print time.
///
/// `labels` uses the configured physical label width/height (thermal/label
/// printer workflow). A4/A5 layouts pack the same labels into a full office
/// page with cut guides so staff can cut and attach them manually.
enum BarcodeOutputLayout { labels, a4Sheet, a5Sheet }

/// Destination selected at print time.
///
/// `configured` follows Printer Settings (system dialog / installed queue /
/// direct ZPL/TSPL network). `systemDialog` and `localPrinter` deliberately let
/// the operator override that destination for one print job without changing
/// branch printer configuration.
enum BarcodePrintDestination { configured, systemDialog, localPrinter }

class BarcodeLabelPrinterService {
  BarcodeLabelPrinterService._();
  static final instance = BarcodeLabelPrinterService._();

  static const int maxCopies = 1000;
  static const int maxBatchLabels = 5000;

  PdfPageFormat pageFormat(PrinterConfig config) {
    final landscape = config.barcodeOrientation == 'landscape';
    final widthMm =
        landscape ? config.barcodeLabelHeightMm : config.barcodeLabelWidthMm;
    final heightMm =
        landscape ? config.barcodeLabelWidthMm : config.barcodeLabelHeightMm;
    return PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
  }

  PdfPageFormat outputFormat(
    PrinterConfig config,
    BarcodeOutputLayout layout,
  ) {
    switch (layout) {
      case BarcodeOutputLayout.a4Sheet:
        return PdfPageFormat(210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm);
      case BarcodeOutputLayout.a5Sheet:
        return PdfPageFormat(148 * PdfPageFormat.mm, 210 * PdfPageFormat.mm);
      case BarcodeOutputLayout.labels:
        return pageFormat(config);
    }
  }

  Future<Uint8List> buildLabelsPdf({
    required PrinterConfig config,
    required String productName,
    String variantDetails = '',
    required String barcode,
    required double price,
    int copies = 1,
  }) {
    return buildBatchLabelsPdf(
      config: config,
      items: [
        BarcodeLabelItem(
          productName: productName,
          variantDetails: variantDetails,
          barcode: barcode,
          price: price,
          copies: copies,
        ),
      ],
    );
  }

  Future<Uint8List> buildBatchLabelsPdf({
    required PrinterConfig config,
    required List<BarcodeLabelItem> items,
  }) async {
    _validateBatch(config, items);

    final doc = pw.Document();
    final format = pageFormat(config);
    for (final item in items) {
      for (var i = 0; i < item.copies; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.all(1.5 * PdfPageFormat.mm),
            build: (_) => _labelBody(config, item),
          ),
        );
      }
    }
    return doc.save();
  }

  /// Builds A4/A5 cut sheets using the branch's configured physical barcode
  /// label dimensions. A light border around every label acts as a cut guide.
  Future<Uint8List> buildSheetPdf({
    required PrinterConfig config,
    required List<BarcodeLabelItem> items,
    required BarcodeOutputLayout layout,
  }) async {
    if (layout == BarcodeOutputLayout.labels) {
      return buildBatchLabelsPdf(config: config, items: items);
    }
    _validateBatch(config, items);

    final format = outputFormat(config, layout);
    final pageWidthMm = format.width / PdfPageFormat.mm;
    final pageHeightMm = format.height / PdfPageFormat.mm;
    const pageMarginMm = 7.0;
    final gapMm = config.barcodeLabelGapMm.clamp(1.5, 6.0).toDouble();
    final landscapeLabel = config.barcodeOrientation == 'landscape';
    final labelWidthMm = landscapeLabel
        ? config.barcodeLabelHeightMm
        : config.barcodeLabelWidthMm;
    final labelHeightMm = landscapeLabel
        ? config.barcodeLabelWidthMm
        : config.barcodeLabelHeightMm;

    final availableWidth = pageWidthMm - (pageMarginMm * 2);
    final availableHeight = pageHeightMm - (pageMarginMm * 2);
    final columns = ((availableWidth + gapMm) / (labelWidthMm + gapMm)).floor();
    final rows = ((availableHeight + gapMm) / (labelHeightMm + gapMm)).floor();
    if (columns < 1 || rows < 1) {
      throw Exception(
        'The configured ${labelWidthMm.toStringAsFixed(0)} × ${labelHeightMm.toStringAsFixed(0)} mm label is too large for this sheet.',
      );
    }

    final expanded = <BarcodeLabelItem>[];
    for (final item in items) {
      for (var i = 0; i < item.copies; i++) {
        expanded.add(item.copyWith(copies: 1));
      }
    }
    final capacity = columns * rows;
    final doc = pw.Document();

    for (var pageStart = 0; pageStart < expanded.length; pageStart += capacity) {
      final pageItems = expanded.sublist(
        pageStart,
        math.min(pageStart + capacity, expanded.length),
      );
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.all(pageMarginMm * PdfPageFormat.mm),
          build: (_) {
            final rowWidgets = <pw.Widget>[];
            for (var row = 0; row < rows; row++) {
              final cells = <pw.Widget>[];
              for (var col = 0; col < columns; col++) {
                final index = (row * columns) + col;
                if (col > 0) {
                  cells.add(pw.SizedBox(width: gapMm * PdfPageFormat.mm));
                }
                if (index < pageItems.length) {
                  cells.add(
                    pw.Container(
                      width: labelWidthMm * PdfPageFormat.mm,
                      height: labelHeightMm * PdfPageFormat.mm,
                      padding: pw.EdgeInsets.all(1.5 * PdfPageFormat.mm),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColors.grey500,
                          width: 0.35,
                        ),
                      ),
                      child: _labelBody(config, pageItems[index]),
                    ),
                  );
                } else {
                  cells.add(
                    pw.SizedBox(
                      width: labelWidthMm * PdfPageFormat.mm,
                      height: labelHeightMm * PdfPageFormat.mm,
                    ),
                  );
                }
              }
              rowWidgets.add(pw.Row(children: cells));
              if (row < rows - 1) {
                rowWidgets.add(pw.SizedBox(height: gapMm * PdfPageFormat.mm));
              }
            }
            return pw.Column(children: rowWidgets);
          },
        ),
      );
    }
    return doc.save();
  }

  Future<void> printLabels({
    required PrinterConfig config,
    required String productName,
    String variantDetails = '',
    required String barcode,
    required double price,
    required int copies,
  }) {
    return printBatch(
      config: config,
      items: [
        BarcodeLabelItem(
          productName: productName,
          variantDetails: variantDetails,
          barcode: barcode,
          price: price,
          copies: copies,
        ),
      ],
    );
  }

  /// Prints one batch using either the configured barcode destination or a
  /// one-off local/system destination selected by the cashier/admin.
  Future<void> printBatch({
    required PrinterConfig config,
    required List<BarcodeLabelItem> items,
    BarcodeOutputLayout layout = BarcodeOutputLayout.labels,
    BarcodePrintDestination destination = BarcodePrintDestination.configured,
    String? localPrinterName,
  }) async {
    _validateBatch(config, items);

    if (destination == BarcodePrintDestination.configured &&
        layout == BarcodeOutputLayout.labels &&
        config.barcodeConnection == 'network') {
      await _printRawNetworkBatch(config: config, items: items);
      return;
    }

    if (destination == BarcodePrintDestination.configured &&
        layout != BarcodeOutputLayout.labels &&
        config.barcodeConnection == 'network') {
      throw Exception(
        'The configured direct-network ZPL/TSPL printer is label-only. Choose a local/system printer for A4 or A5 sheets.',
      );
    }

    final bytes = layout == BarcodeOutputLayout.labels
        ? await buildBatchLabelsPdf(config: config, items: items)
        : await buildSheetPdf(config: config, items: items, layout: layout);
    final format = outputFormat(config, layout);
    final total = items.fold<int>(0, (sum, item) => sum + item.copies);
    final jobName = layout == BarcodeOutputLayout.labels
        ? 'Barcode labels ($total)'
        : 'Barcode ${layout == BarcodeOutputLayout.a4Sheet ? 'A4' : 'A5'} sheet ($total)';

    if (destination == BarcodePrintDestination.systemDialog) {
      await Printing.layoutPdf(
        name: jobName,
        format: format,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
      return;
    }

    if (destination == BarcodePrintDestination.localPrinter) {
      final name = (localPrinterName ?? '').trim();
      if (name.isEmpty) {
        throw Exception('Select a local printer first.');
      }
      await _directPrintPdf(
        printerName: name,
        bytes: bytes,
        format: format,
        jobName: jobName,
        usePrinterSettings: layout == BarcodeOutputLayout.labels,
      );
      return;
    }

    // Configured destination.
    switch (config.barcodeConnection) {
      case 'local':
        final name = (config.barcodeLocalPrinterName ?? '').trim();
        if (name.isEmpty) {
          throw Exception('Select an installed barcode printer first.');
        }
        await _directPrintPdf(
          printerName: name,
          bytes: bytes,
          format: format,
          jobName: jobName,
          usePrinterSettings: layout == BarcodeOutputLayout.labels,
        );
        return;
      case 'dialog':
        await Printing.layoutPdf(
          name: jobName,
          format: format,
          dynamicLayout: false,
          onLayout: (_) async => bytes,
        );
        return;
      case 'network':
        // Network is handled above for label mode and rejected for sheets.
        throw Exception('Unsupported configured barcode destination.');
      default:
        throw Exception('The configured barcode printer connection is invalid.');
    }
  }

  Future<void> testPrint(PrinterConfig config) {
    return printLabels(
      config: config.copyWith(barcodePrintEnabled: true),
      productName: 'Classic T-Shirt',
      variantDetails: 'Black • M',
      barcode: '123456789012',
      price: 9.99,
      copies: 1,
    );
  }

  pw.Widget _labelBody(PrinterConfig config, BarcodeLabelItem item) {
    final safeName = _printableAscii(item.productName, maxLength: 80);
    final safeVariant = _printableAscii(item.variantDetails, maxLength: 50);
    final safeBarcode = _singleLine(item.barcode, maxLength: 100);
    final currency = _printableAscii(config.barcodeCurrency, maxLength: 20);
    final priceText = _priceText(item.price, currency);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        if (config.barcodeShowName)
          pw.SizedBox(
            height: 4.2 * PdfPageFormat.mm,
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
        if (config.barcodeShowVariantDetails && safeVariant.isNotEmpty) ...[
          pw.SizedBox(height: .25 * PdfPageFormat.mm),
          pw.SizedBox(
            height: 3.3 * PdfPageFormat.mm,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                safeVariant,
                maxLines: 1,
                style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey800),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        ],
        pw.SizedBox(height: .6 * PdfPageFormat.mm),
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
          pw.SizedBox(height: .45 * PdfPageFormat.mm),
          pw.SizedBox(
            height: 3 * PdfPageFormat.mm,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(safeBarcode, style: const pw.TextStyle(fontSize: 7)),
            ),
          ),
        ],
        if (config.barcodeShowPrice) ...[
          pw.SizedBox(height: .35 * PdfPageFormat.mm),
          pw.SizedBox(
            height: 4.2 * PdfPageFormat.mm,
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                priceText,
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _directPrintPdf({
    required String printerName,
    required Uint8List bytes,
    required PdfPageFormat format,
    required String jobName,
    required bool usePrinterSettings,
  }) async {
    final selected = await LocalPrinterService.instance.requirePrinter(printerName);
    final printed = await Printing.directPrintPdf(
      printer: selected,
      name: jobName,
      format: format,
      dynamicLayout: false,
      usePrinterSettings: usePrinterSettings,
      onLayout: (_) async => bytes,
    );
    if (!printed) {
      throw Exception(
        'Windows did not accept the barcode print job for "${selected.name}". Check that the printer driver is installed and the printer is online.',
      );
    }
  }

  Future<void> _printRawNetworkBatch({
    required PrinterConfig config,
    required List<BarcodeLabelItem> items,
  }) async {
    final ip = (config.barcodeNetworkIp ?? '').trim();
    if (ip.isEmpty) {
      throw Exception('Barcode printer network address is missing.');
    }

    final language = config.barcodePrinterLanguage.toLowerCase();
    final commands = StringBuffer();
    for (final item in items) {
      switch (language) {
        case 'zpl':
          commands.write(_zpl(config, item));
          break;
        case 'tspl':
          commands.write(_tspl(config, item));
          break;
        default:
          throw Exception(
            'Direct network printing requires a ZPL or TSPL printer profile.',
          );
      }
      commands.writeln();
    }

    final socket = await Socket.connect(
      ip,
      config.barcodeNetworkPort,
      timeout: const Duration(seconds: 7),
    );
    try {
      socket.add(utf8.encode(commands.toString()));
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  String _zpl(PrinterConfig c, BarcodeLabelItem item) {
    final size = _dotSize(c);
    final width = size.$1;
    final height = size.$2;
    final margin = _mmToDots(2, c.barcodeDpi);
    final contentWidth = width - (margin * 2);
    final nameY = _mmToDots(1, c.barcodeDpi);
    final variantY = _mmToDots(4.2, c.barcodeDpi);
    final showVariant = c.barcodeShowVariantDetails && item.variantDetails.trim().isNotEmpty;
    final barcodeY = _mmToDots(showVariant ? 8.0 : 6.0, c.barcodeDpi);
    final barcodeHeight = _mmToDots(
      (height / c.barcodeDpi * 25.4 * .32).clamp(7, 14),
      c.barcodeDpi,
    );
    final valueY = (barcodeY + barcodeHeight + _mmToDots(1, c.barcodeDpi))
        .clamp(0, height - margin)
        .toInt();
    final priceY = (height - _mmToDots(5, c.barcodeDpi))
        .clamp(0, height - margin)
        .toInt();
    final module = (c.barcodeDpi / 203).round().clamp(1, 3);
    final priceText = _priceText(item.price, c.barcodeCurrency.trim());
    final b = StringBuffer('^XA\n^PW$width\n^LL$height\n^LH0,0\n');
    if (c.barcodeShowName) {
      b.writeln(
        '^FO$margin,$nameY^A0N,${_mmToDots(3, c.barcodeDpi)},${_mmToDots(3, c.barcodeDpi)}^FB$contentWidth,1,0,C,0^FD${_zplText(item.productName)}^FS',
      );
    }
    if (showVariant) {
      b.writeln(
        '^FO$margin,$variantY^A0N,${_mmToDots(2.4, c.barcodeDpi)},${_mmToDots(2.4, c.barcodeDpi)}^FB$contentWidth,1,0,C,0^FD${_zplText(item.variantDetails)}^FS',
      );
    }
    b.writeln(
      '^FO$margin,$barcodeY^BY$module,2,$barcodeHeight^BCN,$barcodeHeight,N,N,N^FD${_zplText(item.barcode)}^FS',
    );
    if (c.barcodeShowValue) {
      b.writeln(
        '^FO$margin,$valueY^A0N,${_mmToDots(2.5, c.barcodeDpi)},${_mmToDots(2.5, c.barcodeDpi)}^FB$contentWidth,1,0,C,0^FD${_zplText(item.barcode)}^FS',
      );
    }
    if (c.barcodeShowPrice) {
      b.writeln(
        '^FO$margin,$priceY^A0N,${_mmToDots(4, c.barcodeDpi)},${_mmToDots(4, c.barcodeDpi)}^FB$contentWidth,1,0,C,0^FD${_zplText(priceText)}^FS',
      );
    }
    b.writeln('^PQ${item.copies},0,1,N\n^XZ');
    return b.toString();
  }

  String _tspl(PrinterConfig c, BarcodeLabelItem item) {
    final landscape = c.barcodeOrientation == 'landscape';
    final widthMm = landscape ? c.barcodeLabelHeightMm : c.barcodeLabelWidthMm;
    final heightMm = landscape ? c.barcodeLabelWidthMm : c.barcodeLabelHeightMm;
    final size = _dotSize(c);
    final width = size.$1;
    final height = size.$2;
    final margin = _mmToDots(2, c.barcodeDpi);
    final showVariant = c.barcodeShowVariantDetails && item.variantDetails.trim().isNotEmpty;
    final barcodeY = _mmToDots(showVariant ? 8.0 : 6.0, c.barcodeDpi);
    final barHeight = _mmToDots((heightMm * .32).clamp(7, 14), c.barcodeDpi);
    final priceText = _priceText(item.price, c.barcodeCurrency.trim());
    final b = StringBuffer()
      ..writeln(
          'SIZE ${widthMm.toStringAsFixed(2)} mm,${heightMm.toStringAsFixed(2)} mm')
      ..writeln('GAP ${c.barcodeLabelGapMm.toStringAsFixed(2)} mm,0 mm')
      ..writeln('DIRECTION 1')
      ..writeln('CLS');
    if (c.barcodeShowName) {
      b.writeln(
        'TEXT ${_centerX(width, item.productName, _mmToDots(2.5, c.barcodeDpi))},${_mmToDots(1, c.barcodeDpi)},"3",0,1,1,"${_tsplText(item.productName)}"',
      );
    }
    if (showVariant) {
      b.writeln(
        'TEXT ${_centerX(width, item.variantDetails, _mmToDots(2.1, c.barcodeDpi))},${_mmToDots(4.2, c.barcodeDpi)},"2",0,1,1,"${_tsplText(item.variantDetails)}"',
      );
    }
    b.writeln(
      'BARCODE $margin,$barcodeY,"128",$barHeight,0,0,2,2,"${_tsplText(item.barcode)}"',
    );
    if (c.barcodeShowValue) {
      b.writeln(
        'TEXT ${_centerX(width, item.barcode, _mmToDots(2, c.barcodeDpi))},${barcodeY + barHeight + _mmToDots(1, c.barcodeDpi)},"2",0,1,1,"${_tsplText(item.barcode)}"',
      );
    }
    if (c.barcodeShowPrice) {
      b.writeln(
        'TEXT ${_centerX(width, priceText, _mmToDots(3, c.barcodeDpi))},${(height - _mmToDots(5, c.barcodeDpi)).clamp(0, height - margin).toInt()},"4",0,1,1,"${_tsplText(priceText)}"',
      );
    }
    b.writeln('PRINT 1,${item.copies}');
    return b.toString();
  }

  (int, int) _dotSize(PrinterConfig config) {
    final landscape = config.barcodeOrientation == 'landscape';
    final widthMm =
        landscape ? config.barcodeLabelHeightMm : config.barcodeLabelWidthMm;
    final heightMm =
        landscape ? config.barcodeLabelWidthMm : config.barcodeLabelHeightMm;
    return (
      _mmToDots(widthMm, config.barcodeDpi),
      _mmToDots(heightMm, config.barcodeDpi),
    );
  }

  int _mmToDots(num mm, int dpi) => (mm * dpi / 25.4).round();

  int _centerX(int width, String value, int charWidth) =>
      ((width - (_singleLine(value, maxLength: 80).length * charWidth * .55)) /
              2)
          .round()
          .clamp(0, width)
          .toInt();

  String _singleLine(String value, {required int maxLength}) {
    final result = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return result.length <= maxLength ? result : result.substring(0, maxLength);
  }

  String _zplText(String value) => _printableAscii(value, maxLength: 100)
      .replaceAll('^', ' ')
      .replaceAll('~', ' ');

  String _tsplText(String value) =>
      _printableAscii(value, maxLength: 100).replaceAll('"', "'");

  String _printableAscii(String value, {required int maxLength}) {
    final normalized = value.replaceAll('•', ' / ');
    final singleLine = _singleLine(normalized, maxLength: maxLength);
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

  void _validateBatch(PrinterConfig config, List<BarcodeLabelItem> items) {
    if (!config.barcodePrintEnabled) {
      throw Exception('Barcode printing is disabled for this branch.');
    }
    if (items.isEmpty) throw Exception('Select at least one barcode to print.');

    var total = 0;
    for (final item in items) {
      final barcode = item.barcode.trim();
      if (barcode.isEmpty) {
        throw Exception('${item.productName} does not have a barcode.');
      }
      if (barcode.length > 100) {
        throw Exception('The barcode for ${item.productName} is too long to print.');
      }
      if (barcode.codeUnits.any((unit) => unit < 32 || unit > 126)) {
        throw Exception('Barcode labels support printable ASCII characters only.');
      }
      if (item.copies < 1 || item.copies > maxCopies) {
        throw Exception('Each label quantity must be between 1 and $maxCopies.');
      }
      total += item.copies;
    }
    if (total > maxBatchLabels) {
      throw Exception('A barcode print job can contain at most $maxBatchLabels labels.');
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
      if (!const {'zpl', 'tspl'}
          .contains(config.barcodePrinterLanguage.toLowerCase())) {
        throw Exception('Direct network printing requires ZPL or TSPL.');
      }
    }
  }
}
