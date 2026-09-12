import 'dart:math' as math;
import 'dart:typed_data';

import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/services/barcode_label_printer_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class BarcodeBatchPrintDialog extends StatefulWidget {
  final List<BarcodeLabelItem> items;
  final PrinterConfig config;

  const BarcodeBatchPrintDialog({
    super.key,
    required this.items,
    required this.config,
  });

  @override
  State<BarcodeBatchPrintDialog> createState() => _BarcodeBatchPrintDialogState();
}

class _BarcodeBatchPrintDialogState extends State<BarcodeBatchPrintDialog> {
  BarcodeOutputLayout _layout = BarcodeOutputLayout.labels;
  BarcodePrintDestination _destination = BarcodePrintDestination.configured;
  List<Printer> _printers = const [];
  String? _localPrinterName;
  bool _loadingPrinters = true;
  bool _printing = false;
  int _previewRevision = 0;

  bool get _configuredSheetAllowed => widget.config.barcodeConnection != 'network';

  int get _totalLabels =>
      widget.items.fold<int>(0, (sum, item) => sum + item.copies);

  @override
  void initState() {
    super.initState();
    _loadPrinters();
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

  List<BarcodeLabelItem> _previewItems() {
    var remaining = 48;
    final out = <BarcodeLabelItem>[];
    for (final item in widget.items) {
      if (remaining <= 0) break;
      final copies = math.min(math.min(item.copies, 3), remaining);
      if (copies <= 0) continue;
      out.add(item.copyWith(copies: copies));
      remaining -= copies;
    }
    return out;
  }

  Future<Uint8List> _preview(PdfPageFormat _) {
    final items = _previewItems();
    if (_layout == BarcodeOutputLayout.labels) {
      return BarcodeLabelPrinterService.instance.buildBatchLabelsPdf(
        config: widget.config,
        items: items,
      );
    }
    return BarcodeLabelPrinterService.instance.buildSheetPdf(
      config: widget.config,
      items: items,
      layout: _layout,
    );
  }

  Future<void> _print() async {
    final total = _totalLabels;
    if (total <= 0) return;

    if (total > 250) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm large print job'),
          content: Text('This job contains $total barcode labels. Continue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    if (_layout != BarcodeOutputLayout.labels &&
        _destination == BarcodePrintDestination.configured &&
        !_configuredSheetAllowed) {
      AppFeedback.warning(
        context,
        'A4/A5 sheets cannot be sent as raw ZPL/TSPL. Choose Local / System Printer.',
      );
      return;
    }

    setState(() => _printing = true);
    try {
      await BarcodeLabelPrinterService.instance.printBatch(
        config: widget.config,
        items: widget.items,
        layout: _layout,
        destination: _destination,
        localPrinterName: _localPrinterName,
      );
      if (mounted) Navigator.pop(context, total);
    } catch (e) {
      if (mounted) {
        AppFeedback.error(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 48).clamp(900.0, 1180.0).toDouble();
    final height = (size.height - 44).clamp(620.0, 820.0).toDouble();
    final format =
        BarcodeLabelPrinterService.instance.outputFormat(widget.config, _layout);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review & Print Barcode Labels',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.navy,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Review the combined job, choose output and print destination.',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _printing ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: math.min(360.0, width * .34).toDouble(),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedButton<BarcodeOutputLayout>(
                                segments: const [
                                  ButtonSegment(
                                    value: BarcodeOutputLayout.labels,
                                    icon: Icon(Icons.label_outline_rounded),
                                    label: Text('Labels'),
                                  ),
                                  ButtonSegment(
                                    value: BarcodeOutputLayout.a4Sheet,
                                    label: Text('A4'),
                                  ),
                                  ButtonSegment(
                                    value: BarcodeOutputLayout.a5Sheet,
                                    label: Text('A5'),
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
                              DropdownButtonFormField<BarcodePrintDestination>(
                                value: _destination ==
                                        BarcodePrintDestination.localPrinter
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
                                      'Configured — $_configuredDestination',
                                      overflow: TextOverflow.ellipsis,
                                    ),
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
                              if (_destination !=
                                  BarcodePrintDestination.configured) ...[
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  value: _localPrinterName ?? '__dialog__',
                                  decoration: const InputDecoration(
                                    labelText: 'Local destination',
                                  ),
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
                                              _destination = BarcodePrintDestination.systemDialog;
                                            } else {
                                              _localPrinterName = value;
                                              _destination = BarcodePrintDestination.localPrinter;
                                            }
                                          });
                                        },
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: AppTheme.border),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          child: Row(
                            children: [
                              const Text(
                                'PRINT JOB',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .5,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${widget.items.length} SKU${widget.items.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            itemCount: widget.items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: AppTheme.border),
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 9,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.productName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.navy,
                                            ),
                                          ),
                                          if (item.variantDetails.isNotEmpty)
                                            Text(
                                              item.variantDetails,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.textMuted,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '×${item.copies}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppTheme.border),
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF5F7FA),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.preview_rounded,
                                  size: 18, color: AppTheme.primary),
                              const SizedBox(width: 7),
                              const Text(
                                'Print Preview',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.navy,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _layoutLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: PdfPreview(
                                key: ValueKey(
                                    '${_layout.name}-$_previewRevision-$_totalLabels'),
                                build: _preview,
                                initialPageFormat: format,
                                canChangePageFormat: false,
                                canChangeOrientation: false,
                                allowPrinting: false,
                                allowSharing: false,
                                useActions: false,
                                maxPageWidth: 560,
                                pdfFileName: 'barcode-batch-preview.pdf',
                                loadingWidget: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _previewHint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Row(
                children: [
                  Text(
                    '${widget.items.length} selected SKU${widget.items.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: 14),
                  Container(width: 1, height: 20, color: AppTheme.border),
                  const SizedBox(width: 14),
                  Text(
                    'Total labels: $_totalLabels',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.navy,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _printing ? null : () => Navigator.pop(context),
                    child: const Text('Back'),
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
                    label: Text(
                      _printing ? 'Printing…' : 'Print $_totalLabels Labels',
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  String get _layoutLabel {
    switch (_layout) {
      case BarcodeOutputLayout.a4Sheet:
        return 'A4 CUT SHEET';
      case BarcodeOutputLayout.a5Sheet:
        return 'A5 CUT SHEET';
      case BarcodeOutputLayout.labels:
        return '${widget.config.barcodeLabelWidthMm.toStringAsFixed(0)} × ${widget.config.barcodeLabelHeightMm.toStringAsFixed(0)} MM LABELS';
    }
  }

  String get _previewHint {
    if (_layout == BarcodeOutputLayout.labels) {
      return 'Configured label size. Large jobs are sampled in preview but print at their full quantities.';
    }
    return 'Full-page cut layout using the configured label size. Light borders are printed as cutting guides.';
  }
}
