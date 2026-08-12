import 'dart:math' as math;
import 'dart:typed_data';

import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/services/barcode_label_printer_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class VariantBarcodePrintDialog extends StatefulWidget {
  final int groupId;
  final String groupName;
  final List<Map<String, dynamic>> variants;
  final PrinterConfig config;
  final ProductGroupService service;
  final int? initialProductId;

  const VariantBarcodePrintDialog({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.variants,
    required this.config,
    required this.service,
    this.initialProductId,
  });

  @override
  State<VariantBarcodePrintDialog> createState() =>
      _VariantBarcodePrintDialogState();
}

class _VariantRowState {
  final Map<String, dynamic> variant;
  final TextEditingController quantity;
  bool selected;

  _VariantRowState({
    required this.variant,
    required this.quantity,
    required this.selected,
  });

  void dispose() => quantity.dispose();
}

class _VariantBarcodePrintDialogState extends State<VariantBarcodePrintDialog> {
  late final List<_VariantRowState> _rows;
  BarcodeOutputLayout _layout = BarcodeOutputLayout.labels;
  BarcodePrintDestination _destination = BarcodePrintDestination.configured;
  List<Printer> _printers = const [];
  String? _localPrinterName;
  bool _loadingPrinters = true;
  bool _printing = false;
  bool _generating = false;
  int _previewRevision = 0;

  @override
  void initState() {
    super.initState();
    _rows = widget.variants.map((raw) {
      final v = Map<String, dynamic>.from(raw);
      final id = _int(v['id']);
      final hasBarcode = (v['barcode'] ?? '').toString().trim().isNotEmpty;
      final initial = widget.initialProductId == null
          ? hasBarcode
          : id == widget.initialProductId && hasBarcode;
      return _VariantRowState(
        variant: v,
        quantity: TextEditingController(text: '1'),
        selected: initial,
      );
    }).toList();
    _loadPrinters();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
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

  bool get _configuredSheetAllowed =>
      widget.config.barcodeConnection != 'network';

  List<BarcodeLabelItem> _selectedItems({bool preview = false}) {
    final result = <BarcodeLabelItem>[];
    var previewRemaining = 48;
    for (final row in _rows) {
      if (!row.selected) continue;
      final barcode = (row.variant['barcode'] ?? '').toString().trim();
      if (barcode.isEmpty) continue;
      var copies = int.tryParse(row.quantity.text.trim()) ?? 0;
      if (copies <= 0) continue;
      if (preview) {
        copies = math.min(copies, 3);
        copies = math.min(copies, previewRemaining);
        if (copies <= 0) break;
        previewRemaining -= copies;
      }
      result.add(
        BarcodeLabelItem(
          productName: widget.groupName,
          variantDetails: _variantDetails(row.variant),
          barcode: barcode,
          price: _double(row.variant['price']),
          copies: copies,
        ),
      );
      if (previewRemaining <= 0 && preview) break;
    }
    return result;
  }

  int get _totalLabels => _selectedItems().fold(0, (sum, e) => sum + e.copies);

  Future<Uint8List> _preview(PdfPageFormat _) {
    final items = _selectedItems(preview: true);
    if (items.isEmpty) {
      return BarcodeLabelPrinterService.instance.buildLabelsPdf(
        config: widget.config,
        productName: widget.groupName,
        variantDetails: 'Select a variant',
        barcode: '123456789012',
        price: 0,
      );
    }
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

  void _touchPreview() {
    setState(() => _previewRevision++);
  }

  Future<void> _generateBarcode(_VariantRowState row) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final barcode = await widget.service.generateBarcode();
      final productId = _int(row.variant['id']);
      if (productId == null || productId <= 0) {
        throw Exception('Variant product id is missing.');
      }
      await widget.service.updateVariant(
        widget.groupId,
        productId,
        {'barcode': barcode},
      );
      if (!mounted) return;
      setState(() {
        row.variant['barcode'] = barcode;
        row.selected = true;
        _previewRevision++;
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Barcode generation failed: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _generateMissingBarcodes() async {
    final missing = _rows
        .where((r) => (r.variant['barcode'] ?? '').toString().trim().isEmpty)
        .toList();
    if (missing.isEmpty || _generating) return;
    setState(() => _generating = true);
    var generated = 0;
    try {
      for (final row in missing) {
        final productId = _int(row.variant['id']);
        if (productId == null || productId <= 0) continue;
        final barcode = await widget.service.generateBarcode();
        await widget.service.updateVariant(
          widget.groupId,
          productId,
          {'barcode': barcode},
        );
        row.variant['barcode'] = barcode;
        row.selected = true;
        generated++;
      }
      if (!mounted) return;
      setState(() => _previewRevision++);
      AppFeedback.success(
        context,
        '$generated missing barcode${generated == 1 ? '' : 's'} generated.',
      );
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not generate all barcodes: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _print() async {
    final items = _selectedItems();
    if (items.isEmpty) {
      AppFeedback.warning(context, 'Select at least one variant and enter a label quantity.');
      return;
    }
    final total = items.fold<int>(0, (sum, e) => sum + e.copies);
    if (total > 250) {
      final ok = await showDialog<bool>(
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
      if (ok != true || !mounted) return;
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
        items: items,
        layout: _layout,
        destination: _destination,
        localPrinterName: _localPrinterName,
      );
      if (mounted) Navigator.pop(context, total);
    } catch (e) {
      if (mounted) AppFeedback.error(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final height = (screen.height - 36).clamp(620.0, 840.0).toDouble();
    final width = (screen.width - 48).clamp(980.0, 1320.0).toDouble();
    final missingCount = _rows
        .where((r) => (r.variant['barcode'] ?? '').toString().trim().isEmpty)
        .length;
    final outputFormat =
        BarcodeLabelPrinterService.instance.outputFormat(widget.config, _layout);

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _header(),
            const Divider(height: 1, color: AppTheme.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        _controls(missingCount),
                        const Divider(height: 1, color: AppTheme.border),
                        Expanded(child: _variantTable()),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppTheme.border),
                  Expanded(
                    flex: 4,
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
                                    '${_layout.name}-$_previewRevision-${_totalLabels}'),
                                build: _preview,
                                initialPageFormat: outputFormat,
                                canChangePageFormat: false,
                                canChangeOrientation: false,
                                allowPrinting: false,
                                allowSharing: false,
                                useActions: false,
                                maxPageWidth: 410,
                                pdfFileName: 'barcode-preview.pdf',
                                loadingWidget: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _previewHint,
                            style: const TextStyle(
                              fontSize: 11,
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
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.qr_code_2_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Print Variant Barcodes',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _printing ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _controls(int missingCount) {
    final configuredLabel = _configuredDestinationLabel;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OUTPUT',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: .7,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 7),
          SegmentedButton<BarcodeOutputLayout>(
            segments: const [
              ButtonSegment(
                value: BarcodeOutputLayout.labels,
                label: Text('Configured labels'),
                icon: Icon(Icons.label_outline_rounded),
              ),
              ButtonSegment(
                value: BarcodeOutputLayout.a4Sheet,
                label: Text('A4 cut sheet'),
                icon: Icon(Icons.description_outlined),
              ),
              ButtonSegment(
                value: BarcodeOutputLayout.a5Sheet,
                label: Text('A5 cut sheet'),
                icon: Icon(Icons.article_outlined),
              ),
            ],
            selected: {_layout},
            onSelectionChanged: (values) {
              final next = values.first;
              setState(() {
                _layout = next;
                if (_layout != BarcodeOutputLayout.labels &&
                    _destination == BarcodePrintDestination.configured &&
                    !_configuredSheetAllowed) {
                  _destination = BarcodePrintDestination.systemDialog;
                }
                _previewRevision++;
              });
            },
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
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
                      child: Text('Configured printer — $configuredLabel'),
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
                            if (value == BarcodePrintDestination.configured) {
                              _localPrinterName = null;
                            }
                          });
                        },
                ),
              ),
              if (_destination != BarcodePrintDestination.configured) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
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
                ),
              ],
            ],
          ),
          if (_layout != BarcodeOutputLayout.labels && !_configuredSheetAllowed)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'Your configured barcode printer uses raw ${widget.config.barcodePrinterLanguage.toUpperCase()} network commands, so A4/A5 sheets must use a Windows/local or system printer.',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: _generating || missingCount == 0
                    ? null
                    : _generateMissingBarcodes,
                icon: _generating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 17),
                label: Text(
                  missingCount == 0
                      ? 'All variants have barcodes'
                      : 'Generate $missingCount missing barcode${missingCount == 1 ? '' : 's'}',
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    for (final row in _rows) {
                      row.selected = false;
                    }
                    _previewRevision++;
                  });
                },
                child: const Text('Clear'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {
                  setState(() {
                    for (final row in _rows) {
                      row.selected =
                          (row.variant['barcode'] ?? '').toString().trim().isNotEmpty;
                    }
                    _previewRevision++;
                  });
                },
                child: const Text('Select all with barcode'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _variantTable() {
    if (_rows.isEmpty) {
      return const Center(child: Text('No variants available.'));
    }
    return Column(
      children: [
        Container(
          color: AppTheme.surfaceSoft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: const Row(
            children: [
              SizedBox(width: 34),
              Expanded(flex: 18, child: _Header('VARIANT')),
              Expanded(flex: 16, child: _Header('SKU')),
              Expanded(flex: 18, child: _Header('BARCODE')),
              Expanded(flex: 12, child: _Header('PRICE', right: true)),
              Expanded(flex: 10, child: _Header('STOCK', right: true)),
              SizedBox(width: 86, child: _Header('LABEL QTY', right: true)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _rows.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppTheme.border),
            itemBuilder: (context, index) {
              final row = _rows[index];
              final v = row.variant;
              final barcode = (v['barcode'] ?? '').toString().trim();
              final enabled = barcode.isNotEmpty;
              return Container(
                color: row.selected
                    ? AppTheme.primary.withOpacity(.025)
                    : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Checkbox(
                        value: row.selected,
                        onChanged: !enabled
                            ? null
                            : (value) {
                                setState(() {
                                  row.selected = value == true;
                                  _previewRevision++;
                                });
                              },
                      ),
                    ),
                    Expanded(
                      flex: 18,
                      child: Text(
                        _variantDetails(v).isEmpty ? 'Variant' : _variantDetails(v),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 16,
                      child: Text(
                        (v['sku'] ?? '—').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 18,
                      child: enabled
                          ? Text(
                              barcode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                              ),
                            )
                          : Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Missing',
                                    style: TextStyle(
                                      color: AppTheme.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Generate barcode',
                                  onPressed: _generating
                                      ? null
                                      : () => _generateBarcode(row),
                                  icon: const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 17,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    Expanded(
                      flex: 12,
                      child: Text(
                        AppCurrency.format(_double(v['price'])),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: Text(
                        _stockText(v),
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                    SizedBox(
                      width: 86,
                      child: TextField(
                        controller: row.quantity,
                        enabled: row.selected && enabled && !_printing,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => _touchPreview(),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    final total = _totalLabels;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        children: [
          Text(
            '${_rows.where((r) => r.selected).length} variant${_rows.where((r) => r.selected).length == 1 ? '' : 's'} selected',
            style: const TextStyle(color: AppTheme.textMuted),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 20, color: AppTheme.border),
          const SizedBox(width: 14),
          Text(
            'Total labels: $total',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _printing ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _printing || total == 0 ? null : _print,
            icon: _printing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded),
            label: Text(
              _printing
                  ? 'Printing…'
                  : _layout == BarcodeOutputLayout.labels
                      ? 'Print $total Labels'
                      : 'Print $total on ${_layout == BarcodeOutputLayout.a4Sheet ? 'A4' : 'A5'}',
            ),
          ),
        ],
      ),
    );
  }

  String get _configuredDestinationLabel {
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
      return 'Configured label size. Preview limits large jobs to a few sample labels.';
    }
    return 'Full-page cut layout using the configured label size. Light borders are printed as cutting guides.';
  }

  String _variantDetails(Map<String, dynamic> variant) {
    final color = (variant['variant_color'] ?? '').toString().trim();
    final size = (variant['variant_size'] ?? '').toString().trim();
    return [color, size].where((e) => e.isNotEmpty).join(' • ');
  }

  String _stockText(Map<String, dynamic> variant) {
    final stocks = variant['stocks'];
    if (stocks is List && stocks.isNotEmpty && stocks.first is Map) {
      final raw = (stocks.first as Map)['quantity'];
      final qty = _double(raw);
      return qty == qty.roundToDouble()
          ? qty.toInt().toString()
          : qty.toStringAsFixed(2);
    }
    final qty = _double(variant['stock_qty'] ?? variant['stock']);
    if (qty == 0) return '0';
    return qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _Header extends StatelessWidget {
  final String text;
  final bool right;

  const _Header(this.text, {this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: .45,
        fontWeight: FontWeight.w900,
        color: AppTheme.textMuted,
      ),
    );
  }
}
