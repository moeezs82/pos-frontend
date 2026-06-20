import 'dart:typed_data';

import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Live thermal receipt preview. Renders through the exact same
/// [ReceiptPreviewService] the app uses for real receipts, with realistic
/// sample data. The narrow constrained width mimics what the roll will look
/// like coming out of the printer — not an A4 page.
class InvoiceTemplatePreviewScreen extends StatefulWidget {
  final List<InvoiceTemplate> templates;
  final InvoiceTemplate initialTemplate;
  final String shopName;
  final String? shopAddress;
  final String? shopPhone;
  final List<String> footerLines;

  const InvoiceTemplatePreviewScreen({
    super.key,
    this.templates = InvoiceTemplate.values,
    this.initialTemplate = InvoiceTemplate.standard,
    this.shopName = 'My Shop',
    this.shopAddress,
    this.shopPhone,
    this.footerLines = const ['Thank you, visit again!', 'Follow us on Instagram @myshop'],
  });

  @override
  State<InvoiceTemplatePreviewScreen> createState() => _InvoiceTemplatePreviewScreenState();
}

class _InvoiceTemplatePreviewScreenState extends State<InvoiceTemplatePreviewScreen> {
  late InvoiceTemplate _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTemplate;
  }

  List<ReceiptItem> get _sampleItems => [
        ReceiptItem(name: 'Chicken Karahi (Half)', price: 850, qty: 1, total: 850),
        ReceiptItem(name: 'Plain Naan', price: 30, qty: 4, total: 120),
        ReceiptItem(name: 'Soft Drink 1.5L', price: 150, qty: 1, total: 150),
      ];

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    return ReceiptPreviewService.instance.buildReceiptPdf(
      shopName: widget.shopName,
      shopAddress: widget.shopAddress,
      shopPhone: widget.shopPhone,
      receiptNo: 'SAMPLE-0001',
      dateTime: DateTime.now(),
      items: _sampleItems,
      subtotal: 1120,
      discount: 20,
      tax: 0,
      grandTotal: 1100,
      meta: const {
        'customer_snapshot': {'name': 'Walk-in Customer', 'phone': '0300-1234567'},
        'cash_received': 1200,
        'change_amount': 100,
      },
      sections: _selected.sections,
      paperWidth: _selected.paperWidthCode,
      footerLines: widget.footerLines,
    );
  }

  /// Pixel width we give the PdfPreview widget on screen for each paper size.
  /// Keeps the receipt narrow so it visually matches what comes off the roll.
  double get _previewWidth => _selected.paperWidthCode == 'mm58' ? 230 : 320;

  @override
  Widget build(BuildContext context) {
    final bg = Colors.grey.shade700;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Receipt Preview'),
        backgroundColor: Colors.grey.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.templates.map((t) {
                final isSelected = t == _selected;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selected = t),
                  selectedColor: AppTheme.primary,
                  backgroundColor: Colors.grey.shade600,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Template description strip
          Container(
            width: double.infinity,
            color: Colors.grey.shade800,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              _selected.description,
              style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),

          // Receipt viewer — narrow, centred, on a counter-like grey surface
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Container(
                    width: _previewWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    // PdfPreview fills the constrained box
                    child: AspectRatio(
                      // Roll paper is very tall — use a generous ratio
                      aspectRatio: _selected.paperWidthCode == 'mm58' ? 0.38 : 0.42,
                      child: PdfPreview(
                        key: ValueKey(_selected),
                        build: _buildPdf,
                        initialPageFormat:
                            _selected.paperWidthCode == 'mm58' ? PdfPageFormat.roll57 : PdfPageFormat.roll80,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        allowPrinting: false,
                        allowSharing: false,
                        canDebug: false,
                        useActions: false,
                        scrollViewDecoration: const BoxDecoration(color: Colors.white),
                        pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
                        actions: const [],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom info bar
          Container(
            color: Colors.grey.shade800,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.straighten_rounded, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  'Paper: ${_selected.paperWidthCode == 'mm58' ? '58 mm' : '80 mm'} thermal roll',
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
