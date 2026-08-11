import 'dart:typed_data';

import 'package:enterprise_pos/models/invoice_template.dart';
import 'package:enterprise_pos/services/receipt_preview_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Live print-template preview rendered by the same PDF engine used by local
/// Windows printing and the system print dialog.
class InvoiceTemplatePreviewScreen extends StatefulWidget {
  final List<InvoiceTemplate> templates;
  final InvoiceTemplate initialTemplate;
  final String shopName;
  final String? shopAddress;
  final String? shopPhone;
  final List<String> footerLines;
  final String? receiptHeader;
  final String invoicePaperSize;
  final String invoiceHeading;
  final bool showLogo;
  final String? logoData;
  final bool showQr;
  final String? qrUrl;
  final String qrCaption;

  const InvoiceTemplatePreviewScreen({
    super.key,
    this.templates = InvoiceTemplate.values,
    this.initialTemplate = InvoiceTemplate.standard,
    this.shopName = 'My Shop',
    this.shopAddress,
    this.shopPhone,
    this.footerLines = const [
      'Thank you, visit again!',
      'Follow us on Instagram @myshop',
    ],
    this.receiptHeader,
    this.invoicePaperSize = 'a4',
    this.invoiceHeading = 'SALES INVOICE',
    this.showLogo = false,
    this.logoData,
    this.showQr = false,
    this.qrUrl,
    this.qrCaption = 'Scan to review us',
  });

  @override
  State<InvoiceTemplatePreviewScreen> createState() =>
      _InvoiceTemplatePreviewScreenState();
}

class _InvoiceTemplatePreviewScreenState
    extends State<InvoiceTemplatePreviewScreen> {
  late InvoiceTemplate _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTemplate;
  }

  String get _paperCode =>
      _selected.isPaged ? widget.invoicePaperSize : _selected.paperWidthCode;

  List<ReceiptItem> get _sampleItems => [
        ReceiptItem(
          name: 'Classic T-Shirt / Black / M',
          unitName: 'PCS',
          price: 1250,
          qty: 1,
          discountAmount: 50,
          total: 1200,
        ),
        ReceiptItem(
          name: 'Coca Cola 500ml',
          unitName: 'PCS',
          price: 120,
          qty: 3,
          discountAmount: 0,
          total: 360,
        ),
        ReceiptItem(
          name: 'USB Cable 1m',
          unitName: 'PCS',
          price: 350,
          qty: 1,
          discountAmount: 0,
          total: 350,
        ),
      ];

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    return ReceiptPreviewService.instance.buildReceiptPdf(
      shopName: widget.shopName,
      shopAddress: widget.shopAddress,
      shopPhone: widget.shopPhone,
      receiptNo: 'SAMPLE-0001',
      dateTime: DateTime.now(),
      items: _sampleItems,
      subtotal: 1960,
      discount: 50,
      tax: 0,
      grandTotal: 1910,
      meta: const {
        'customer_snapshot': {
          'name': 'Walk-in Customer',
          'phone': '0300-1234567',
        },
        'payments_snapshot': [
          {'method': 'cash', 'label': 'Cash', 'amount': 1000},
          {'method': 'card', 'label': 'Card', 'amount': 910},
        ],
        'cash_received': 1000,
        'change_amount': 0,
      },
      sections: _selected.sections,
      paperWidth: _paperCode,
      footerLines: widget.footerLines,
      receiptHeader: widget.receiptHeader,
      invoiceHeading: widget.invoiceHeading,
      showLogo: widget.showLogo && _selected.isCustomerFacing,
      logoData: widget.logoData,
      showQr: widget.showQr && _selected.isCustomerFacing,
      qrUrl: widget.qrUrl,
      qrCaption: widget.qrCaption,
    );
  }

  double get _previewWidth {
    if (_selected.isPaged) {
      return _paperCode == 'a5' ? 490 : 690;
    }
    return _paperCode == 'mm58' ? 230 : 320;
  }

  double get _previewAspectRatio {
    if (_selected.isPaged) {
      if (_paperCode == 'letter') return 8.5 / 11.0;
      return 1 / 1.4142;
    }
    return _paperCode == 'mm58' ? 0.38 : 0.42;
  }

  String get _paperLabel {
    switch (_paperCode) {
      case 'a4':
        return 'A4 portrait page';
      case 'a5':
        return 'A5 portrait page';
      case 'letter':
        return 'Letter portrait page';
      case 'mm58':
        return '58 mm thermal roll';
      default:
        return '80 mm thermal roll';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Colors.grey.shade700;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Print Template Preview'),
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
          Container(
            width: double.infinity,
            color: Colors.grey.shade800,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              _selected.description,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
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
                      child: AspectRatio(
                        aspectRatio: _previewAspectRatio,
                        child: PdfPreview(
                          key: ValueKey('${_selected.value}-$_paperCode'),
                          build: _buildPdf,
                          initialPageFormat: ReceiptPreviewService.instance
                              .pageFormatForPaperWidth(_paperCode),
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          allowPrinting: false,
                          allowSharing: false,
                          canDebug: false,
                          useActions: false,
                          scrollViewDecoration:
                              const BoxDecoration(color: Colors.white),
                          pdfPreviewPageDecoration:
                              const BoxDecoration(color: Colors.white),
                          actions: const [],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: Colors.grey.shade800,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.straighten_rounded,
                  size: 14,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  'Paper: $_paperLabel',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
