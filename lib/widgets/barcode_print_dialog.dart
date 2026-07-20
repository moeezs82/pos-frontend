import 'dart:typed_data';

import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/services/barcode_label_printer_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class BarcodePrintDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final PrinterConfig config;

  const BarcodePrintDialog({
    super.key,
    required this.product,
    required this.config,
  });

  @override
  State<BarcodePrintDialog> createState() => _BarcodePrintDialogState();
}

class _BarcodePrintDialogState extends State<BarcodePrintDialog> {
  final _quantityController = TextEditingController(text: '1');
  bool _printing = false;
  String? _error;

  String get _name => (widget.product['name'] ?? 'Product').toString().trim();
  String get _barcode => (widget.product['barcode'] ?? '').toString().trim();
  double get _price => double.tryParse((widget.product['price'] ?? '0').toString()) ?? 0;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<Uint8List> _preview(PdfPageFormat _) {
    return BarcodeLabelPrinterService.instance.buildLabelsPdf(
      config: widget.config,
      productName: _name,
      barcode: _barcode,
      price: _price,
      copies: 1,
    );
  }

  String get _destination {
    switch (widget.config.barcodeConnection) {
      case 'local':
        return widget.config.barcodeLocalPrinterName ?? 'Installed printer';
      case 'network':
        final ip = widget.config.barcodeNetworkIp ?? 'Network printer';
        return '$ip:${widget.config.barcodeNetworkPort} (${widget.config.barcodePrinterLanguage.toUpperCase()})';
      default:
        return 'System print dialog';
    }
  }

  Future<void> _print() async {
    final copies = int.tryParse(_quantityController.text.trim());
    if (copies == null || copies < 1 || copies > BarcodeLabelPrinterService.maxCopies) {
      setState(() => _error = 'Enter a quantity from 1 to ${BarcodeLabelPrinterService.maxCopies}.');
      return;
    }

    if (copies > 250) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm large print job'),
          content: Text('Print $copies barcode labels for “$_name”?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await BarcodeLabelPrinterService.instance.printLabels(
        config: widget.config,
        productName: _name,
        barcode: _barcode,
        price: _price,
        copies: copies,
      );
      if (mounted) Navigator.pop(context, copies);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = BarcodeLabelPrinterService.instance.pageFormat(widget.config);
    final widthMm = format.width / PdfPageFormat.mm;
    final heightMm = format.height / PdfPageFormat.mm;
    final dialogHeight = (MediaQuery.sizeOf(context).height - 40).clamp(520.0, 760.0).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 680,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Print Barcode Labels', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _printing ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Barcode: $_barcode  •  Destination: $_destination', style: const TextStyle(color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PdfPreview(
                    build: _preview,
                    initialPageFormat: format,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    allowPrinting: false,
                    allowSharing: false,
                    useActions: false,
                    maxPageWidth: 430,
                    pdfFileName: 'barcode-label.pdf',
                    loadingWidget: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Configured label: ${widthMm.toStringAsFixed(0)} × ${heightMm.toStringAsFixed(0)} mm at ${widget.config.barcodeDpi} DPI',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _quantityController,
                enabled: !_printing,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _print(),
                decoration: InputDecoration(
                  labelText: 'Number of labels',
                  hintText: 'Example: 50',
                  helperText: 'One label per page. Maximum ${BarcodeLabelPrinterService.maxCopies} labels per job.',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.copy_all_rounded),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _printing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _printing ? null : _print,
                    icon: _printing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.print_rounded),
                    label: Text(_printing ? 'Printing…' : 'Print Labels'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
