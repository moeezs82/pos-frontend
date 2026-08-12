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
  BarcodeOutputLayout _layout = BarcodeOutputLayout.labels;
  BarcodePrintDestination _destination = BarcodePrintDestination.configured;
  List<Printer> _printers = const [];
  String? _localPrinterName;
  bool _loadingPrinters = true;
  bool _printing = false;
  String? _error;
  int _previewRevision = 0;

  String get _name =>
      (widget.product['_barcode_label_name'] ?? widget.product['name'] ?? 'Product')
          .toString()
          .trim();
  String get _barcode => (widget.product['barcode'] ?? '').toString().trim();
  double get _price =>
      double.tryParse((widget.product['price'] ?? '0').toString()) ?? 0;
  String get _variantDetails {
    final override =
        (widget.product['_barcode_variant_details'] ?? '').toString().trim();
    if (override.isNotEmpty) return override;
    final color = (widget.product['variant_color'] ?? '').toString().trim();
    final size = (widget.product['variant_size'] ?? '').toString().trim();
    return [color, size].where((e) => e.isNotEmpty).join(' • ');
  }

  bool get _configuredSheetAllowed =>
      widget.config.barcodeConnection != 'network';

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _loadingPrinters = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPrinters = false);
    }
  }

  Future<Uint8List> _preview(PdfPageFormat _) {
    final item = BarcodeLabelItem(
      productName: _name,
      variantDetails: _variantDetails,
      barcode: _barcode,
      price: _price,
      copies: _layout == BarcodeOutputLayout.labels ? 1 : _previewCopies,
    );
    if (_layout == BarcodeOutputLayout.labels) {
      return BarcodeLabelPrinterService.instance.buildBatchLabelsPdf(
        config: widget.config,
        items: [item],
      );
    }
    return BarcodeLabelPrinterService.instance.buildSheetPdf(
      config: widget.config,
      items: [item],
      layout: _layout,
    );
  }

  int get _previewCopies {
    final copies = int.tryParse(_quantityController.text.trim()) ?? 1;
    return copies.clamp(1, 48).toInt();
  }

  Future<void> _print() async {
    final copies = int.tryParse(_quantityController.text.trim());
    if (copies == null ||
        copies < 1 ||
        copies > BarcodeLabelPrinterService.maxCopies) {
      setState(() => _error =
          'Enter a quantity from 1 to ${BarcodeLabelPrinterService.maxCopies}.');
      return;
    }

    if (_layout != BarcodeOutputLayout.labels &&
        _destination == BarcodePrintDestination.configured &&
        !_configuredSheetAllowed) {
      setState(() => _error =
          'A4/A5 sheets require a local/system printer because the configured printer uses raw ZPL/TSPL.');
      return;
    }

    if (copies > 250) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm large print job'),
          content: Text('Print $copies barcode labels for “$_name”?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue')),
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
      await BarcodeLabelPrinterService.instance.printBatch(
        config: widget.config,
        items: [
          BarcodeLabelItem(
            productName: _name,
            variantDetails: _variantDetails,
            barcode: _barcode,
            price: _price,
            copies: copies,
          ),
        ],
        layout: _layout,
        destination: _destination,
        localPrinterName: _localPrinterName,
      );
      if (mounted) Navigator.pop(context, copies);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final format =
        BarcodeLabelPrinterService.instance.outputFormat(widget.config, _layout);
    final dialogHeight = (MediaQuery.sizeOf(context).height - 40)
        .clamp(620.0, 820.0)
        .toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 820,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Print Barcode Labels',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed:
                        _printing ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _variantDetails.isEmpty ? _name : '$_name  •  $_variantDetails',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                'Barcode: $_barcode',
                style: const TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),
              SegmentedButton<BarcodeOutputLayout>(
                segments: const [
                  ButtonSegment(
                    value: BarcodeOutputLayout.labels,
                    icon: Icon(Icons.label_outline_rounded),
                    label: Text('Configured labels'),
                  ),
                  ButtonSegment(
                    value: BarcodeOutputLayout.a4Sheet,
                    icon: Icon(Icons.description_outlined),
                    label: Text('A4 cut sheet'),
                  ),
                  ButtonSegment(
                    value: BarcodeOutputLayout.a5Sheet,
                    icon: Icon(Icons.article_outlined),
                    label: Text('A5 cut sheet'),
                  ),
                ],
                selected: {_layout},
                onSelectionChanged: _printing
                    ? null
                    : (values) {
                        setState(() {
                          _layout = values.first;
                          if (_layout != BarcodeOutputLayout.labels &&
                              _destination ==
                                  BarcodePrintDestination.configured &&
                              !_configuredSheetAllowed) {
                            _destination =
                                BarcodePrintDestination.systemDialog;
                          }
                          _previewRevision++;
                        });
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<BarcodePrintDestination>(
                      value: _destination == BarcodePrintDestination.localPrinter
                          ? BarcodePrintDestination.systemDialog
                          : _destination,
                      decoration: const InputDecoration(
                        labelText: 'Print using',
                        prefixIcon: Icon(Icons.print_rounded),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: BarcodePrintDestination.configured,
                          enabled: _layout == BarcodeOutputLayout.labels ||
                              _configuredSheetAllowed,
                          child: Text(
                              'Configured printer — $_configuredDestination'),
                        ),
                        const DropdownMenuItem(
                          value: BarcodePrintDestination.systemDialog,
                          child: Text('Local / system printer'),
                        ),
                      ],
                      onChanged: _printing
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _destination = value;
                                if (value ==
                                    BarcodePrintDestination.configured) {
                                  _localPrinterName = null;
                                }
                              });
                            },
                    ),
                  ),
                  if (_destination !=
                      BarcodePrintDestination.configured) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _localPrinterName ?? '__dialog__',
                        decoration:
                            const InputDecoration(labelText: 'Local destination'),
                        items: [
                          const DropdownMenuItem(
                            value: '__dialog__',
                            child: Text('System print dialog'),
                          ),
                          ..._printers.map(
                            (p) => DropdownMenuItem(
                              value: p.name,
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: _loadingPrinters || _printing
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == null || value == '__dialog__') {
                                    _localPrinterName = null;
                                    _destination =
                                        BarcodePrintDestination.systemDialog;
                                  } else {
                                    _localPrinterName = value;
                                    _destination =
                                        BarcodePrintDestination.localPrinter;
                                  }
                                });
                              },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PdfPreview(
                    key: ValueKey('${_layout.name}-$_previewRevision'),
                    build: _preview,
                    initialPageFormat: format,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    allowPrinting: false,
                    allowSharing: false,
                    useActions: false,
                    maxPageWidth: 500,
                    pdfFileName: 'barcode-preview.pdf',
                    loadingWidget:
                        const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _layout == BarcodeOutputLayout.labels
                    ? 'Uses the configured ${widget.config.barcodeLabelWidthMm.toStringAsFixed(0)} × ${widget.config.barcodeLabelHeightMm.toStringAsFixed(0)} mm label size.'
                    : 'The page is filled with configured-size barcode labels and printed cut guides for manual cutting.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _quantityController,
                enabled: !_printing,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _previewRevision++),
                onSubmitted: (_) => _print(),
                decoration: InputDecoration(
                  labelText: 'Number of labels',
                  hintText: 'Example: 50',
                  helperText:
                      'For A4/A5 the app automatically fills as many labels per page as possible.',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.copy_all_rounded),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _printing ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _printing ? null : _print,
                    icon: _printing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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

  String get _configuredDestination {
    switch (widget.config.barcodeConnection) {
      case 'local':
        return widget.config.barcodeLocalPrinterName ?? 'Installed printer';
      case 'network':
        return '${widget.config.barcodeNetworkIp ?? 'Network'}:${widget.config.barcodeNetworkPort}';
      default:
        return 'System dialog';
    }
  }
}
