import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:enterprise_pos/models/barcode_label_line.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/services/local_printer_service.dart';
import 'package:enterprise_pos/services/pdf_arabic_font_loader.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BarcodeLabelItem {
  final String productName;
  final String variantDetails;
  final String barcode;
  final double price;
  final String sku;

  /// The product's own discount, exactly as stored on the product. The label
  /// never invents a discount: `discount <= 0` means the discount and sale
  /// price lines simply do not print for this item.
  final double discount;

  /// 'percentage' or 'fixed'. Anything else is treated as 'percentage', which
  /// matches how the sale screens read the same column.
  final String discountType;
  final int copies;

  const BarcodeLabelItem({
    required this.productName,
    this.variantDetails = '',
    required this.barcode,
    required this.price,
    this.sku = '',
    this.discount = 0,
    this.discountType = 'percentage',
    this.copies = 1,
  });

  bool get _isFixedDiscount => discountType.toLowerCase().trim() == 'fixed';

  /// The money taken off one unit. Clamped to the price so a mis-keyed
  /// discount can never print a negative sale price on a shelf label.
  double get discountAmount {
    if (discount <= 0 || price <= 0) return 0;
    final raw = _isFixedDiscount ? discount : price * (discount / 100);
    if (raw <= 0) return 0;
    return raw > price ? price : raw;
  }

  /// Percentage equivalent of [discountAmount], for display only.
  double get discountPercent {
    if (price <= 0) return 0;
    return (discountAmount / price) * 100;
  }

  bool get hasDiscount => discountAmount > 0.004;

  double get salePrice => price - discountAmount;

  BarcodeLabelItem copyWith({int? copies}) => BarcodeLabelItem(
        productName: productName,
        variantDetails: variantDetails,
        barcode: barcode,
        price: price,
        sku: sku,
        discount: discount,
        discountType: discountType,
        copies: copies ?? this.copies,
      );

  /// Reads the fields a barcode label needs off a product/variant map as the
  /// products and product-group endpoints return it. Keeping this in one place
  /// is what stops the simple-product dialog and the variant dialog from
  /// drifting apart.
  static BarcodeLabelItem fromProduct(
    Map<String, dynamic> product, {
    String? nameOverride,
    String? variantOverride,
    int copies = 1,
  }) {
    double toDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse((v ?? '').toString()) ?? 0;

    final variant = (variantOverride ?? '').trim().isNotEmpty
        ? variantOverride!.trim()
        : [
            (product['variant_color'] ?? '').toString().trim(),
            (product['variant_size'] ?? '').toString().trim(),
          ].where((e) => e.isNotEmpty).join(' / ');

    return BarcodeLabelItem(
      productName: (nameOverride ?? product['name'] ?? 'Product').toString().trim(),
      variantDetails: variant,
      barcode: (product['barcode'] ?? '').toString().trim(),
      price: toDouble(product['price']),
      sku: (product['sku'] ?? '').toString().trim(),
      discount: toDouble(product['discount']),
      discountType: (product['discount_type'] ?? 'percentage').toString(),
      copies: copies,
    );
  }
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

/// One line of a label after the branch's design has been applied to a
/// specific product: the design says "print the sale price prefixed with
/// 'Now:'", this says "print `Now: 45.00 KD` at normal size".
class ResolvedLabelLine {
  final BarcodeLabelField field;
  final String text;
  final BarcodeLabelTextSize size;

  const ResolvedLabelLine({
    required this.field,
    required this.text,
    required this.size,
  });

  bool get isGraphic => field.isGraphic;
}

/// How the resolved lines are fitted to the physical label.
///
/// [textScale] shrinks every text line by the same factor so the design keeps
/// its relative proportions instead of some lines vanishing; [barcodeHeightMm]
/// is what is left over for the symbol, never below [_minBarcodeMm] because a
/// bar shorter than that stops scanning reliably.
class _LabelLayout {
  final double textScale;
  final double barcodeHeightMm;

  const _LabelLayout({required this.textScale, required this.barcodeHeightMm});
}

class BarcodeLabelPrinterService {
  BarcodeLabelPrinterService._();
  static final instance = BarcodeLabelPrinterService._();

  static const int maxCopies = 1000;
  static const int maxBatchLabels = 5000;

  /// Nominal height of one text line, before [_LabelLayout.textScale].
  static const Map<BarcodeLabelTextSize, double> _lineHeightsMm = {
    BarcodeLabelTextSize.small: 3.0,
    BarcodeLabelTextSize.normal: 4.2,
    BarcodeLabelTextSize.large: 5.4,
  };

  /// Nominal font size matching [_lineHeightsMm]. A FittedBox still scales a
  /// long line down horizontally; this only sets the starting point.
  static const Map<BarcodeLabelTextSize, double> _fontSizes = {
    BarcodeLabelTextSize.small: 6.8,
    BarcodeLabelTextSize.normal: 8.4,
    BarcodeLabelTextSize.large: 11.0,
  };

  static const double _lineGapMm = 0.35;
  static const double _labelPaddingMm = 1.5;

  /// Below roughly 6 mm of bar height, handheld scanners start missing reads,
  /// so text is squeezed before the symbol is.
  static const double _minBarcodeMm = 6.0;

  /// Text is never scaled below this: an unreadable price is worse than a
  /// label that overflows slightly, and the settings preview shows the result.
  static const double _minTextScale = 0.42;

  /// TSPL bitmap polarity.
  ///
  /// TSPL's BITMAP command treats a CLEARED bit as a printed (black) dot,
  /// which is the opposite of ZPL's ^GF. If Urdu/Arabic labels ever come out
  /// of a TSPL printer as white-on-black, flip this to false — it is the only
  /// thing that needs to change.
  static const bool _tsplBitmapInverted = true;

  static Future<ArabicPdfFonts?>? _fontsFuture;

  /// Loads a Unicode-capable font once per process.
  ///
  /// PDF's built-in Type1 fonts (Helvetica/Courier/Times) have no Unicode
  /// support at all, so without this an Urdu or Arabic shop name either throws
  /// or prints as blanks. This reuses the same system-font lookup the Arabic
  /// receipt templates already rely on, which keeps label printing fully
  /// offline on a POS workstation.
  static Future<ArabicPdfFonts?> _unicodeFonts() {
    return (_fontsFuture ??= loadSystemArabicPdfFonts().catchError(
      (Object _) => null,
    ));
  }

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

  // ── design resolution ──────────────────────────────────────────────────────

  /// Applies the branch's label design to one product.
  ///
  /// Lines with nothing to say are dropped here rather than rendered blank:
  /// a simple product has no variant details, most products have no discount,
  /// and a shop that leaves the custom-text word empty gets no empty row. That
  /// is what lets the same design serve discounted and undiscounted stock.
  List<ResolvedLabelLine> resolveLines(
    PrinterConfig config,
    BarcodeLabelItem item,
  ) {
    final currency = _sanitize(config.barcodeCurrency, maxLength: 20);
    final out = <ResolvedLabelLine>[];

    for (final line in config.effectiveLabelLines) {
      if (!line.enabled) continue;

      final label = line.label.trim();
      String? value;

      switch (line.field) {
        case BarcodeLabelField.shopName:
          value = (config.shopName ?? '').trim();
          break;
        case BarcodeLabelField.productName:
          value = item.productName.trim();
          break;
        case BarcodeLabelField.variantDetails:
          value = item.variantDetails.trim();
          break;
        case BarcodeLabelField.price:
          value = item.price > 0 ? _priceText(item.price, currency) : null;
          break;
        case BarcodeLabelField.discount:
          value = item.hasDiscount ? _discountText(item, currency) : null;
          break;
        case BarcodeLabelField.salePrice:
          value = item.hasDiscount ? _priceText(item.salePrice, currency) : null;
          break;
        case BarcodeLabelField.barcode:
          // The symbol itself carries no text; the digits are their own line.
          out.add(ResolvedLabelLine(
            field: line.field,
            text: item.barcode.trim(),
            size: line.size,
          ));
          continue;
        case BarcodeLabelField.barcodeValue:
          value = item.barcode.trim();
          break;
        case BarcodeLabelField.sku:
          value = item.sku.trim();
          break;
        case BarcodeLabelField.customText:
          // The whole content of a custom line is the word the branch typed,
          // so an empty one has nothing to print.
          if (label.isNotEmpty) {
            out.add(ResolvedLabelLine(
              field: line.field,
              text: _sanitize(label, maxLength: 80),
              size: line.size,
            ));
          }
          continue;
      }

      if (value == null || value.isEmpty) continue;
      final text = _sanitize(
        label.isEmpty ? value : '$label $value',
        maxLength: 90,
      );
      if (text.isEmpty) continue;
      out.add(ResolvedLabelLine(field: line.field, text: text, size: line.size));
    }

    return out;
  }

  /// "10% (5.00 KD)" for a percentage discount, "5.00 KD (10%)" for a fixed
  /// one — the branch sees the form it entered first, and the other form is
  /// what the customer actually cares about.
  String _discountText(BarcodeLabelItem item, String currency) {
    final amount = _priceText(item.discountAmount, currency);
    final percent = _trimZeros(item.discountPercent);
    if (item.discountType.toLowerCase().trim() == 'fixed') {
      return '$amount ($percent%)';
    }
    return '$percent% ($amount)';
  }

  String _trimZeros(double value) {
    final fixed = value.toStringAsFixed(2);
    if (fixed.endsWith('.00')) return fixed.substring(0, fixed.length - 3);
    if (fixed.endsWith('0')) return fixed.substring(0, fixed.length - 1);
    return fixed;
  }

  // ── layout ─────────────────────────────────────────────────────────────────

  /// Fits [lines] into [contentHeightMm].
  ///
  /// Text is shrunk first, down to [_minTextScale]; the symbol only gives up
  /// height once the text has nothing left to give, and never past
  /// [_minBarcodeMm]. A design that still does not fit prints slightly tight
  /// rather than dropping a line the branch asked for — the settings preview
  /// is where that gets noticed.
  _LabelLayout _layoutFor(List<ResolvedLabelLine> lines, double contentHeightMm) {
    final textLines = lines.where((l) => !l.isGraphic).toList();
    final hasBarcode = lines.any((l) => l.isGraphic);

    var textTotal = 0.0;
    for (final line in textLines) {
      textTotal += _lineHeightsMm[line.size] ?? 4.2;
    }
    final gapCount = math.max(0, lines.length - 1);
    final double gaps = gapCount.toDouble() * _lineGapMm;

    if (!hasBarcode) {
      if (textTotal <= 0) {
        return const _LabelLayout(textScale: 1.0, barcodeHeightMm: 0);
      }
      final scale = ((contentHeightMm - gaps) / textTotal).clamp(_minTextScale, 1.0);
      return _LabelLayout(textScale: scale.toDouble(), barcodeHeightMm: 0);
    }

    final roomAtFullText = contentHeightMm - gaps - textTotal;
    if (roomAtFullText >= _minBarcodeMm) {
      // The text fits at full size, so every millimetre left over goes to the
      // symbol — a taller bar only ever helps scanning.
      return _LabelLayout(textScale: 1.0, barcodeHeightMm: roomAtFullText);
    }

    final textRoom = contentHeightMm - gaps - _minBarcodeMm;
    final scale = textTotal <= 0
        ? 1.0
        : (textRoom / textTotal).clamp(_minTextScale, 1.0).toDouble();
    return _LabelLayout(textScale: scale, barcodeHeightMm: _minBarcodeMm);
  }

  // ── PDF rendering ──────────────────────────────────────────────────────────

  Future<Uint8List> buildLabelsPdf({
    required PrinterConfig config,
    required String productName,
    String variantDetails = '',
    required String barcode,
    required double price,
    String sku = '',
    double discount = 0,
    String discountType = 'percentage',
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
          sku: sku,
          discount: discount,
          discountType: discountType,
          copies: copies,
        ),
      ],
    );
  }

  Future<pw.Document> _newDocument() async {
    final fonts = await _unicodeFonts();
    if (fonts == null) return pw.Document();
    return pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
  }

  Future<Uint8List> buildBatchLabelsPdf({
    required PrinterConfig config,
    required List<BarcodeLabelItem> items,
  }) async {
    _validateBatch(config, items);

    final doc = await _newDocument();
    final format = pageFormat(config);
    for (final item in items) {
      final lines = resolveLines(config, item);
      for (var i = 0; i < item.copies; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.all(_labelPaddingMm * PdfPageFormat.mm),
            build: (_) => _labelBody(
              lines,
              heightMm: _labelHeightMm(config) - (_labelPaddingMm * 2),
            ),
          ),
        );
      }
    }
    return doc.save();
  }

  double _labelHeightMm(PrinterConfig config) =>
      config.barcodeOrientation == 'landscape'
          ? config.barcodeLabelWidthMm
          : config.barcodeLabelHeightMm;

  double _labelWidthMm(PrinterConfig config) =>
      config.barcodeOrientation == 'landscape'
          ? config.barcodeLabelHeightMm
          : config.barcodeLabelWidthMm;

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
    final labelWidthMm = _labelWidthMm(config);
    final labelHeightMm = _labelHeightMm(config);

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
    final doc = await _newDocument();
    final contentHeightMm = labelHeightMm - (_labelPaddingMm * 2);

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
                      padding: pw.EdgeInsets.all(_labelPaddingMm * PdfPageFormat.mm),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColors.grey500,
                          width: 0.35,
                        ),
                      ),
                      child: _labelBody(
                        resolveLines(config, pageItems[index]),
                        heightMm: contentHeightMm,
                      ),
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

  pw.Widget _labelBody(List<ResolvedLabelLine> lines, {required double heightMm}) {
    if (lines.isEmpty) {
      return pw.Center(
        child: pw.Text('No label lines enabled',
            style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
      );
    }

    final layout = _layoutFor(lines, heightMm);
    final children = <pw.Widget>[];

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) {
        children.add(pw.SizedBox(height: _lineGapMm * PdfPageFormat.mm));
      }
      final line = lines[i];

      if (line.isGraphic) {
        children.add(
          pw.SizedBox(
            height: layout.barcodeHeightMm * PdfPageFormat.mm,
            child: pw.Padding(
              padding: pw.EdgeInsets.symmetric(horizontal: 1.2 * PdfPageFormat.mm),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: line.text,
                drawText: false,
              ),
            ),
          ),
        );
        continue;
      }

      final heightsMm = (_lineHeightsMm[line.size] ?? 4.2) * layout.textScale;
      final fontSize = (_fontSizes[line.size] ?? 8.4) * layout.textScale;
      final emphasised = line.field == BarcodeLabelField.productName ||
          line.field == BarcodeLabelField.salePrice ||
          line.field == BarcodeLabelField.price;

      children.add(
        pw.SizedBox(
          height: heightsMm * PdfPageFormat.mm,
          child: pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            child: pw.Text(
              line.text,
              maxLines: 1,
              // Urdu and Arabic labels have to lay out right-to-left or the
              // prefix word and its value come out in the wrong order.
              textDirection:
                  _isRtl(line.text) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: emphasised ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: line.field == BarcodeLabelField.variantDetails
                    ? PdfColors.grey800
                    : PdfColors.black,
              ),
            ),
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: children,
    );
  }

  // ── printing ───────────────────────────────────────────────────────────────

  Future<void> printLabels({
    required PrinterConfig config,
    required String productName,
    String variantDetails = '',
    required String barcode,
    required double price,
    String sku = '',
    double discount = 0,
    String discountType = 'percentage',
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
          sku: sku,
          discount: discount,
          discountType: discountType,
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
    return printBatch(
      config: config.copyWith(barcodePrintEnabled: true),
      items: const [
        BarcodeLabelItem(
          productName: 'Classic T-Shirt',
          variantDetails: 'Black / M',
          barcode: '123456789012',
          price: 9.99,
          sku: 'TS-BLK-M',
          discount: 10,
          discountType: 'percentage',
          copies: 1,
        ),
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

  // ── raw ZPL / TSPL ─────────────────────────────────────────────────────────

  /// True when any line on any label needs glyphs a label printer's resident
  /// fonts cannot produce — Urdu and Arabic above all, but equally an accented
  /// Latin shop name.
  bool _needsUnicode(PrinterConfig config, List<BarcodeLabelItem> items) {
    for (final item in items) {
      for (final line in resolveLines(config, item)) {
        if (line.isGraphic) continue;
        for (final rune in line.text.runes) {
          if (rune > 126) return true;
        }
      }
    }
    return false;
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
    if (language != 'zpl' && language != 'tspl') {
      throw Exception(
        'Direct network printing requires a ZPL or TSPL printer profile.',
      );
    }

    // A ZPL/TSPL printer draws text with its own resident fonts, which are
    // Latin-only. When the design contains Urdu, Arabic or any other non-ASCII
    // text, the label is rendered here instead and sent as a bitmap, so the
    // printer reproduces exactly what the on-screen preview showed.
    final unicode = _needsUnicode(config, items);
    final payload = unicode
        ? await _rasterCommands(config: config, items: items, language: language)
        : _textCommands(config: config, items: items, language: language);

    final socket = await Socket.connect(
      ip,
      config.barcodeNetworkPort,
      timeout: const Duration(seconds: 7),
    );
    try {
      socket.add(payload);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  /// Native printer-font commands. Fast and compact, ASCII only.
  List<int> _textCommands({
    required PrinterConfig config,
    required List<BarcodeLabelItem> items,
    required String language,
  }) {
    final buffer = StringBuffer();
    final contentHeightMm = _labelHeightMm(config) - (_labelPaddingMm * 2);
    for (final item in items) {
      final lines = resolveLines(config, item);
      final layout = _layoutFor(lines, contentHeightMm);
      buffer.write(language == 'zpl'
          ? _zpl(config, item, lines, layout, contentHeightMm)
          : _tspl(config, item, lines, layout, contentHeightMm));
      buffer.writeln();
    }
    return _latin1(buffer.toString());
  }

  /// Walks the resolved lines top to bottom and hands back the vertical
  /// position of each, in millimetres, using the same layout the PDF used. One
  /// measurement pass shared by ZPL and TSPL is what keeps the three renderers
  /// producing the same label instead of three slightly different ones.
  List<double> _lineOffsetsMm(
    List<ResolvedLabelLine> lines,
    _LabelLayout layout,
    double contentHeightMm,
  ) {
    var total = 0.0;
    for (final line in lines) {
      total += line.isGraphic
          ? layout.barcodeHeightMm
          : (_lineHeightsMm[line.size] ?? 4.2) * layout.textScale;
    }
    total += math.max(0, lines.length - 1).toDouble() * _lineGapMm;

    // The PDF centres its column vertically; starting the raw-command layout
    // at the same offset is what keeps a ZPL/TSPL label lined up with the
    // preview instead of riding high on the stock.
    final slack = math.max(0.0, contentHeightMm - total);
    var y = _labelPaddingMm + (slack / 2);

    final offsets = <double>[];
    for (final line in lines) {
      offsets.add(y);
      y += line.isGraphic
          ? layout.barcodeHeightMm
          : (_lineHeightsMm[line.size] ?? 4.2) * layout.textScale;
      y += _lineGapMm;
    }
    return offsets;
  }

  String _zpl(
    PrinterConfig c,
    BarcodeLabelItem item,
    List<ResolvedLabelLine> lines,
    _LabelLayout layout,
    double contentHeightMm,
  ) {
    final size = _dotSize(c);
    final width = size.$1;
    final height = size.$2;
    final margin = _mmToDots(_labelPaddingMm, c.barcodeDpi);
    final contentWidth = math.max(1, width - (margin * 2));
    final offsets = _lineOffsetsMm(lines, layout, contentHeightMm);
    final module = (c.barcodeDpi / 203).round().clamp(1, 3);

    final b = StringBuffer('^XA\n^PW$width\n^LL$height\n^LH0,0\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final y = _mmToDots(offsets[i], c.barcodeDpi).clamp(0, height).toInt();

      if (line.isGraphic) {
        final barHeight = _mmToDots(layout.barcodeHeightMm, c.barcodeDpi);
        b.writeln(
          '^FO$margin,$y^BY$module,2,$barHeight^BCN,$barHeight,N,N,N^FD${_zplText(line.text)}^FS',
        );
        continue;
      }

      final lineHeight = (_lineHeightsMm[line.size] ?? 4.2) * layout.textScale;
      // ZPL character height is the cell height; ~78% of the line box keeps a
      // little leading between rows, matching the PDF's FittedBox result.
      final glyph = _mmToDots(lineHeight * 0.78, c.barcodeDpi).clamp(6, 400).toInt();
      b.writeln(
        '^FO$margin,$y^A0N,$glyph,$glyph^FB$contentWidth,1,0,C,0^FD${_zplText(line.text)}^FS',
      );
    }
    b.writeln('^PQ${item.copies},0,1,N\n^XZ');
    return b.toString();
  }

  String _tspl(
    PrinterConfig c,
    BarcodeLabelItem item,
    List<ResolvedLabelLine> lines,
    _LabelLayout layout,
    double contentHeightMm,
  ) {
    final widthMm = _labelWidthMm(c);
    final heightMm = _labelHeightMm(c);
    final size = _dotSize(c);
    final width = size.$1;
    final margin = _mmToDots(_labelPaddingMm, c.barcodeDpi);
    final offsets = _lineOffsetsMm(lines, layout, contentHeightMm);

    final b = StringBuffer()
      ..writeln('SIZE ${widthMm.toStringAsFixed(2)} mm,${heightMm.toStringAsFixed(2)} mm')
      ..writeln('GAP ${c.barcodeLabelGapMm.toStringAsFixed(2)} mm,0 mm')
      ..writeln('DIRECTION 1')
      ..writeln('CLS');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final y = _mmToDots(offsets[i], c.barcodeDpi);

      if (line.isGraphic) {
        final barHeight = _mmToDots(layout.barcodeHeightMm, c.barcodeDpi);
        b.writeln(
          'BARCODE $margin,$y,"128",$barHeight,0,0,2,2,"${_tsplText(line.text)}"',
        );
        continue;
      }

      // TSPL resident fonts are fixed sizes, so the nearest one is chosen and
      // then multiplied. Font "2" ≈ 12 dots tall, "3" ≈ 16, "4" ≈ 24 at 203 dpi.
      final lineHeightDots =
          _mmToDots((_lineHeightsMm[line.size] ?? 4.2) * layout.textScale, c.barcodeDpi);
      final (font, baseDots) = lineHeightDots >= 22
          ? ('4', 24)
          : lineHeightDots >= 15
              ? ('3', 16)
              : ('2', 12);
      final mul = (lineHeightDots / baseDots).floor().clamp(1, 4);
      final charWidth = (baseDots * mul * 0.55).round();
      b.writeln(
        'TEXT ${_centerX(width, line.text, charWidth)},$y,"$font",0,$mul,$mul,"${_tsplText(line.text)}"',
      );
    }

    b.writeln('PRINT 1,${item.copies}');
    return b.toString();
  }

  /// Renders each label to a monochrome bitmap and sends it as a graphic.
  ///
  /// This is the Urdu/Arabic path: the printer never sees text, only dots, so
  /// script shaping, right-to-left ordering and font choice are all settled
  /// here by the same PDF renderer that drew the preview.
  Future<List<int>> _rasterCommands({
    required PrinterConfig config,
    required List<BarcodeLabelItem> items,
    required String language,
  }) async {
    final info = await Printing.info();
    if (!info.canRaster) {
      throw Exception(
        'This device cannot render Urdu/Arabic labels for a direct-network ZPL/TSPL printer. '
        'Print through the installed printer driver instead, or use Latin text only on the label.',
      );
    }

    final dpi = config.barcodeDpi.toDouble();
    final out = <int>[];

    for (final item in items) {
      // One page per item; copies are handled by the printer's own quantity
      // command so the bitmap crosses the wire once.
      final single = item.copyWith(copies: 1);
      final pdf = await buildBatchLabelsPdf(config: config, items: [single]);
      final raster = await Printing.raster(pdf, dpi: dpi).first;
      final bitmap = _MonoBitmap.fromRgba(
        raster.pixels,
        raster.width,
        raster.height,
      );

      if (language == 'zpl') {
        out.addAll(_latin1(_zplGraphic(config, bitmap, item.copies)));
      } else {
        out.addAll(_tsplGraphic(config, bitmap, item.copies));
      }
    }
    return out;
  }

  String _zplGraphic(PrinterConfig c, _MonoBitmap bitmap, int copies) {
    final size = _dotSize(c);
    final hex = StringBuffer();
    for (final byte in bitmap.bytes) {
      hex.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    final total = bitmap.bytes.length;
    return '^XA\n^PW${size.$1}\n^LL${size.$2}\n^LH0,0\n'
        '^FO0,0^GFA,$total,$total,${bitmap.bytesPerRow},${hex.toString()}^FS\n'
        '^PQ$copies,0,1,N\n^XZ\n';
  }

  List<int> _tsplGraphic(PrinterConfig c, _MonoBitmap bitmap, int copies) {
    final widthMm = _labelWidthMm(c);
    final heightMm = _labelHeightMm(c);
    final header = StringBuffer()
      ..writeln('SIZE ${widthMm.toStringAsFixed(2)} mm,${heightMm.toStringAsFixed(2)} mm')
      ..writeln('GAP ${c.barcodeLabelGapMm.toStringAsFixed(2)} mm,0 mm')
      ..writeln('DIRECTION 1')
      ..writeln('CLS')
      ..write('BITMAP 0,0,${bitmap.bytesPerRow},${bitmap.height},0,');

    final out = <int>[];
    out.addAll(_latin1(header.toString()));
    out.addAll(
      _tsplBitmapInverted
          ? bitmap.bytes.map((b) => (~b) & 0xFF)
          : bitmap.bytes,
    );
    out.addAll(_latin1('\r\nPRINT 1,$copies\r\n'));
    return out;
  }

  /// Encodes command text as single bytes. Only ever called with ASCII, but
  /// going through a fixed encoding keeps the socket payload byte-exact
  /// alongside raw bitmap data.
  List<int> _latin1(String value) {
    final out = <int>[];
    for (final unit in value.codeUnits) {
      out.add(unit <= 0xFF ? unit : 0x3F);
    }
    return out;
  }

  (int, int) _dotSize(PrinterConfig config) => (
        _mmToDots(_labelWidthMm(config), config.barcodeDpi),
        _mmToDots(_labelHeightMm(config), config.barcodeDpi),
      );

  int _mmToDots(num mm, int dpi) => (mm * dpi / 25.4).round();

  int _centerX(int width, String value, int charWidth) =>
      ((width - (value.length * charWidth)) / 2).round().clamp(0, width).toInt();

  // ── text handling ──────────────────────────────────────────────────────────

  /// Arabic script blocks, which cover Urdu as well as Arabic, Persian and
  /// Pashto. Used to pick the text direction, not to filter anything out.
  static bool _isRtl(String value) {
    for (final rune in value.runes) {
      if ((rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF) ||
          (rune >= 0xFB50 && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF) ||
          (rune >= 0x0590 && rune <= 0x05FF)) {
        return true;
      }
    }
    return false;
  }

  /// Collapses a value to one printable line.
  ///
  /// Unlike the ASCII-only sanitiser this replaced, every script survives here
  /// — only control characters are dropped, and the length limit counts runes
  /// so an Urdu or Arabic name is never cut through the middle of a character.
  String _sanitize(String value, {required int maxLength}) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final kept = StringBuffer();
    for (final rune in collapsed.runes) {
      if (rune < 32 || (rune >= 0x7F && rune <= 0x9F)) continue;
      kept.writeCharCode(rune);
    }
    final result = kept.toString();
    final runes = result.runes.toList();
    if (runes.length <= maxLength) return result;
    return String.fromCharCodes(runes.take(maxLength));
  }

  /// ZPL reserves ^ and ~ as control characters. This path only ever receives
  /// ASCII text (the Unicode case goes through the bitmap renderer).
  String _zplText(String value) =>
      _sanitize(value, maxLength: 100).replaceAll('^', ' ').replaceAll('~', ' ');

  String _tsplText(String value) =>
      _sanitize(value, maxLength: 100).replaceAll('"', "'").replaceAll('\\', '/');

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

    // The design may legitimately omit the symbol (a plain price tag), in
    // which case a product without a barcode is still printable.
    final needsBarcode = config.effectiveLabelLines.any(
      (line) =>
          line.enabled &&
          (line.field == BarcodeLabelField.barcode ||
              line.field == BarcodeLabelField.barcodeValue),
    );

    var total = 0;
    for (final item in items) {
      final barcode = item.barcode.trim();
      if (needsBarcode) {
        if (barcode.isEmpty) {
          throw Exception('${item.productName} does not have a barcode.');
        }
        if (barcode.length > 100) {
          throw Exception('The barcode for ${item.productName} is too long to print.');
        }
        // Code 128 encodes ASCII only. This applies to the barcode value
        // itself — the surrounding text lines accept any script.
        if (barcode.codeUnits.any((unit) => unit < 32 || unit > 126)) {
          throw Exception(
            'Barcode values support printable ASCII characters only. '
            '"${item.productName}" has a barcode that cannot be encoded.',
          );
        }
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

/// A 1-bit-per-pixel image, packed MSB-first with a set bit meaning a black
/// dot — the convention ZPL's ^GF uses directly and TSPL's BITMAP uses
/// inverted.
class _MonoBitmap {
  final int width;
  final int height;
  final int bytesPerRow;
  final Uint8List bytes;

  const _MonoBitmap({
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bytes,
  });

  /// Thresholds an RGBA raster to black and white.
  ///
  /// Anti-aliased edges from the PDF rasteriser land either side of mid-grey;
  /// a fully transparent pixel is treated as white so a label with no
  /// background still prints as ink-on-paper rather than a solid block.
  factory _MonoBitmap.fromRgba(Uint8List pixels, int width, int height) {
    final bytesPerRow = (width + 7) ~/ 8;
    final out = Uint8List(bytesPerRow * height);

    for (var y = 0; y < height; y++) {
      final rowStart = y * bytesPerRow;
      for (var x = 0; x < width; x++) {
        final i = ((y * width) + x) * 4;
        if (i + 3 >= pixels.length) continue;
        final alpha = pixels[i + 3];
        if (alpha < 128) continue;
        // Rec. 601 luma, integer maths to stay fast on large batches.
        final luma =
            ((pixels[i] * 299) + (pixels[i + 1] * 587) + (pixels[i + 2] * 114)) ~/
                1000;
        if (luma >= 128) continue;
        out[rowStart + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }

    return _MonoBitmap(
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      bytes: out,
    );
  }
}
