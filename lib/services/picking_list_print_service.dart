import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_arabic_font_loader.dart';

class PickingListPrintService {
  const PickingListPrintService();

  Future<Uint8List> buildPdf(Map<String, dynamic> data) async {
    final fonts = await loadSystemArabicPdfFonts();
    final base = fonts?.regular ?? pw.Font.helvetica();
    final bold = fonts?.bold ?? pw.Font.helveticaBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: base, bold: bold),
    );

    final branch = _map(data['branch']);
    final branchName = _text(branch['name'], fallback: 'CounterIQ');
    final from = _text(data['date_from']);
    final to = _text(data['date_to']);
    final generated = _text(data['generated_at']);
    final sales = _int(data['sale_count']);
    final productCount = _int(data['product_count']);
    final totalQty = _qty(data['total_quantity']);
    final excludedReturns = _number(data['excluded_return_quantity']);
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 30),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'CounterIQ Picking List',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'PICKING LIST',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(branchName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    if (from.isNotEmpty || to.isNotEmpty)
                      pw.Text(
                        from == to ? 'Sales date: $from' : 'Sales period: $from to $to',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Generated', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  pw.Text(generated, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _metric('Sales', '$sales'),
              pw.SizedBox(width: 8),
              _metric('Products / Variants', '$productCount'),
              pw.SizedBox(width: 8),
              _metric('Total Qty', totalQty),
            ],
          ),
          if (excludedReturns > 0) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: PdfColors.amber50,
                border: pw.Border.all(color: PdfColors.amber300, width: .6),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              child: pw.Text(
                '${_qty(excludedReturns)} return quantity excluded from this fulfillment list.',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ),
          ],
          pw.SizedBox(height: 14),
          _table(items),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            child: pw.Text(
              'Picking rule: current active positive sale quantities only. Negative return rows are not items to pick.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<void> printOrSave(Map<String, dynamic> data) async {
    final bytes = await buildPdf(data);
    final from = _text(data['date_from']).replaceAll('-', '');
    final to = _text(data['date_to']).replaceAll('-', '');
    final suffix = from == to ? from : '${from}_$to';
    await Printing.layoutPdf(
      name: suffix.isEmpty ? 'CounterIQ Picking List' : 'CounterIQ Picking List $suffix',
      format: PdfPageFormat.a4,
      dynamicLayout: false,
      onLayout: (_) async => bytes,
    );
  }

  pw.Widget _metric(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: .6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  pw.Widget _table(List<Map<String, dynamic>> items) {
    final headerStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 8);

    pw.Widget cell(String value, {pw.TextAlign align = pw.TextAlign.left, bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: pw.Text(
            value,
            textAlign: align,
            style: bold ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold) : cellStyle,
          ),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        children: [
          cell('#', bold: true),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Product', style: headerStyle)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Variant', style: headerStyle)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('SKU / Barcode', style: headerStyle)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Unit', style: headerStyle)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Sales', style: headerStyle, textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Qty to Pick', style: headerStyle, textAlign: pw.TextAlign.right)),
        ],
      ),
    ];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final secondary = _text(item['secondary_name']);
      final name = _text(item['name'], fallback: 'Product #${item['product_id']}');
      final product = secondary.isEmpty ? name : '$name\n$secondary';
      final size = _text(item['variant_size']);
      final color = _text(item['variant_color']);
      final variant = [size, color].where((v) => v.isNotEmpty).join(' / ');
      final sku = _text(item['sku']);
      final barcode = _text(item['barcode']);
      final identity = [sku, barcode].where((v) => v.isNotEmpty).join('\n');
      final unit = _text(item['unit_short_name'], fallback: _text(item['unit_name'], fallback: '—'));
      rows.add(
        pw.TableRow(
          decoration: i.isOdd ? const pw.BoxDecoration(color: PdfColors.grey50) : null,
          children: [
            cell('${i + 1}'),
            cell(product, bold: true),
            cell(variant.isEmpty ? '—' : variant),
            cell(identity.isEmpty ? '—' : identity),
            cell(unit),
            cell('${_int(item['sale_count'])}', align: pw.TextAlign.center),
            cell(_qty(item['quantity']), align: pw.TextAlign.right, bold: true),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text('No positive sale quantities found for this period.', style: cellStyle),
            ),
            pw.SizedBox(), pw.SizedBox(), pw.SizedBox(), pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: .45),
      columnWidths: const {
        0: pw.FixedColumnWidth(24),
        1: pw.FlexColumnWidth(2.6),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.35),
        4: pw.FlexColumnWidth(.75),
        5: pw.FlexColumnWidth(.65),
        6: pw.FlexColumnWidth(.9),
      },
      children: rows,
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  static String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _qty(dynamic value) {
    final number = _number(value);
    if ((number - number.roundToDouble()).abs() < 0.0000001) {
      return number.toStringAsFixed(0);
    }
    var text = number.toStringAsFixed(3);
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return text;
  }
}
