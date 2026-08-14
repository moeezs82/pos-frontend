import 'dart:io';

import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/forms/variable_product_form_screen.dart';
import 'package:enterprise_pos/models/printer_config.dart';
import 'package:enterprise_pos/providers/branch_provider.dart';
import 'package:enterprise_pos/providers/printer_config_provider.dart';
import 'package:enterprise_pos/services/app_currency.dart' show AppCurrency;
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/barcode_print_dialog.dart';
import 'package:enterprise_pos/widgets/variant_barcode_print_dialog.dart';
import 'package:enterprise_pos/widgets/enterprise/enterprise_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// Detail screen for a variable product group.
/// Shows metadata in a structured info card + all variants in a polished table.
class ProductGroupDetailScreen extends StatefulWidget {
  final int groupId;
  final String groupName;

  const ProductGroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ProductGroupDetailScreen> createState() =>
      _ProductGroupDetailScreenState();
}

class _ProductGroupDetailScreenState extends State<ProductGroupDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _group;
  List<Map<String, dynamic>> _variants = [];
  bool _changed = false;

  late ProductGroupService _service;
  late ProductService _productService;

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _service = ProductGroupService(token: token);
    _productService = ProductService(token: token);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.showGroup(widget.groupId);
      if (!mounted) return;
      setState(() {
        _group = data['group'] is Map
            ? Map<String, dynamic>.from(data['group'] as Map)
            : null;
        final raw = data['products'] as List? ?? [];
        _variants = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to load group: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editGroup() async {
    if (_group == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => VariableProductFormScreen(group: _group)),
    );
    if (result == true && mounted) {
      _changed = true;
      _load();
    }
  }

  Future<void> _addVariant() async {
    final result = await _showAddVariantDialog();
    if (result == true && mounted) {
      _changed = true;
      _load();
    }
  }

  Future<PrinterConfig?> _barcodeConfig() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('print-barcode-labels')) {
      AppFeedback.error(context, 'You do not have permission to print product labels.');
      return null;
    }
    if (!auth.hasAddon('barcode_labels')) {
      AppFeedback.warning(context, 'Barcode Label Printing is not active for this branch.');
      return null;
    }
    final provider = context.read<PrinterConfigProvider>();
    try {
      final token = auth.token;
      if (token == null) throw Exception('Your session has expired. Please sign in again.');
      await provider.refresh(token);
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Could not load barcode printer settings: $e');
      return null;
    }
    if (!mounted) return null;
    final config = provider.config.copyWith(
      barcodeCurrency: context.read<BranchProvider>().currency,
    );
    if (!config.isBarcodeConfigured) {
      AppFeedback.warning(
        context,
        config.barcodeAddonActive
            ? 'Ask a Master Admin to configure Barcode Label Printing for this branch.'
            : 'Barcode Label Printing is not active for this branch.',
      );
      return null;
    }
    return config;
  }

  Future<void> _printGroupBarcodes() async {
    if (_variants.isEmpty) return;
    final config = await _barcodeConfig();
    if (config == null || !mounted) return;
    final copies = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VariantBarcodePrintDialog(
        groupId: widget.groupId,
        groupName: _group?['name']?.toString() ?? widget.groupName,
        variants: _variants,
        config: config,
        service: _service,
      ),
    );
    if (!mounted) return;
    // Refresh after every batch dialog close because Generate Missing Barcodes
    // can persist child-product barcodes even when the user decides not to print.
    await _load();
    if (copies != null && mounted) {
      AppFeedback.success(context, '$copies barcode label${copies == 1 ? '' : 's'} sent to print.');
    }
  }

  Future<void> _printOneVariant(Map<String, dynamic> variant) async {
    final barcode = (variant['barcode'] ?? '').toString().trim();
    if (barcode.isEmpty) {
      AppFeedback.warning(context, 'Generate a barcode for this variant before printing.');
      return;
    }
    final config = await _barcodeConfig();
    if (config == null || !mounted) return;
    final payload = Map<String, dynamic>.from(variant)
      ..['_barcode_label_name'] = _group?['name']?.toString() ?? widget.groupName
      ..['_barcode_variant_details'] = [
        (variant['variant_color'] ?? '').toString().trim(),
        (variant['variant_size'] ?? '').toString().trim(),
      ].where((e) => e.isNotEmpty).join(' • ');
    final copies = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BarcodePrintDialog(product: payload, config: config),
    );
    if (copies != null && mounted) {
      AppFeedback.success(context, '$copies barcode label${copies == 1 ? '' : 's'} sent to print.');
    }
  }

  Future<String?> _pickVariantImage(BuildContext feedbackContext) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.single.path == null) return null;
    final file = result.files.single;
    if (file.size > 2 * 1024 * 1024) {
      if (feedbackContext.mounted) {
        AppFeedback.error(feedbackContext, 'Product images must be 2 MB or smaller.');
      }
      return null;
    }
    return file.path;
  }

  Widget _variantImageEditor({
    required String? pickedPath,
    required String? currentUrl,
    required bool removeCurrent,
    required VoidCallback? onPick,
    required VoidCallback? onRemove,
  }) {
    final hasPicked = pickedPath != null && pickedPath.isNotEmpty;
    final hasCurrent =
        !hasPicked && !removeCurrent && currentUrl != null && currentUrl.isNotEmpty;

    Widget preview;
    if (hasPicked) {
      preview = Image.file(
        File(pickedPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: AppTheme.textMuted),
        ),
      );
    } else if (hasCurrent) {
      preview = Image.network(
        currentUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: AppTheme.textMuted),
        ),
      );
    } else {
      preview = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 32, color: AppTheme.textMuted),
            SizedBox(height: 5),
            Text('No variant image',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 145,
          decoration: BoxDecoration(
            color: AppTheme.surfaceSoft,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              preview,
              if (hasPicked || hasCurrent)
                Positioned(
                  right: 8,
                  top: 8,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      tooltip: 'Remove image',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      onPressed: onRemove,
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.image_outlined, size: 17),
            label: Text(hasPicked || hasCurrent ? 'Replace Image' : 'Choose Image'),
          ),
        ),
        const Text(
          'JPG, PNG, or WebP · maximum 2 MB',
          style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  // ── Add Variant dialog ────────────────────────────────────────────────────

  Future<bool?> _showAddVariantDialog() async {
    final sizeCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    final secondaryNameCtrl = TextEditingController(
      text: (_group?['secondary_name'] ?? '').toString(),
    );
    final priceCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final stockCtrl = TextEditingController();
    final wholesaleCtrl = TextEditingController();
    final discountCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    final reorderCtrl = TextEditingController(text: '0');
    bool skuBusy = false;
    bool barcodeBusy = false;
    bool saving = false;
    String discountType = 'percentage';
    String? imagePath;
    final groupName = _group?['name']?.toString() ?? widget.groupName;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 780),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
                  decoration: const BoxDecoration(
                    color: AppTheme.surfaceSoft,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          size: 19,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add Variant',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.navy,
                              ),
                            ),
                            Text(
                              'Add one sellable SKU to $groupName',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppTheme.textMuted,
                          size: 18,
                        ),
                        onPressed: saving ? null : () => Navigator.pop(ctx, false),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        splashRadius: 16,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _dlgLabel('Dimensions'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _dlgField(sizeCtrl, 'Size (e.g. S, M, XL)')),
                            const SizedBox(width: 10),
                            Expanded(child: _dlgField(colorCtrl, 'Color (e.g. Black)')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _dlgField(secondaryNameCtrl, 'Secondary Name'),
                        const SizedBox(height: 16),
                        _dlgLabel('Product Image'),
                        const SizedBox(height: 8),
                        _variantImageEditor(
                          pickedPath: imagePath,
                          currentUrl: null,
                          removeCurrent: false,
                          onPick: saving
                              ? null
                              : () async {
                                  final picked = await _pickVariantImage(ctx);
                                  if (picked != null && ctx.mounted) {
                                    setSt(() => imagePath = picked);
                                  }
                                },
                          onRemove: saving
                              ? null
                              : () => setSt(() => imagePath = null),
                        ),
                        const SizedBox(height: 16),
                        _dlgLabel('Pricing'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _dlgField(
                                priceCtrl,
                                'Retail Price *',
                                numeric: true,
                                required: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _dlgField(
                                wholesaleCtrl,
                                'Wholesale Price',
                                numeric: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _dlgField(costCtrl, 'Cost Price', numeric: true)),
                            const SizedBox(width: 10),
                            Expanded(child: _dlgField(stockCtrl, 'Opening Stock', numeric: true)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _dlgField(
                                discountCtrl,
                                discountType == 'fixed'
                                    ? 'Discount (Fixed Amount)'
                                    : 'Discount (%)',
                                numeric: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: discountType,
                                decoration: const InputDecoration(
                                  labelText: 'Discount Type',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'percentage',
                                    child: Text('Percentage (%)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'fixed',
                                    child: Text('Fixed Amount'),
                                  ),
                                ],
                                onChanged: saving
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setSt(() => discountType = value);
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _dlgField(reorderCtrl, 'Reorder Level', numeric: true),
                        const SizedBox(height: 16),
                        _dlgLabel('Identification'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _dlgField(skuCtrl, 'SKU *', required: true)),
                            const SizedBox(width: 8),
                            _genBtn(
                              label: 'Auto SKU',
                              icon: Icons.auto_awesome_rounded,
                              busy: skuBusy,
                              onTap: saving
                                  ? null
                                  : () async {
                                      setSt(() => skuBusy = true);
                                      try {
                                        final sku = await _service.generateSKU(
                                          groupName: groupName,
                                          size: sizeCtrl.text.trim(),
                                          color: colorCtrl.text.trim(),
                                        );
                                        if (ctx.mounted) skuCtrl.text = sku;
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          AppFeedback.error(ctx, 'SKU generation failed: $e');
                                        }
                                      } finally {
                                        if (ctx.mounted) setSt(() => skuBusy = false);
                                      }
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _dlgField(barcodeCtrl, 'Barcode')),
                            const SizedBox(width: 8),
                            _genBtn(
                              label: 'Auto',
                              icon: Icons.qr_code_2_rounded,
                              busy: barcodeBusy,
                              onTap: saving
                                  ? null
                                  : () async {
                                      setSt(() => barcodeBusy = true);
                                      try {
                                        final barcode = await _service.generateBarcode();
                                        if (ctx.mounted) barcodeCtrl.text = barcode;
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          AppFeedback.error(ctx, 'Barcode generation failed: $e');
                                        }
                                      } finally {
                                        if (ctx.mounted) setSt(() => barcodeBusy = false);
                                      }
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          foregroundColor: AppTheme.textMuted,
                          minimumSize: const Size(90, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final price = double.tryParse(priceCtrl.text) ?? 0;
                                final wholesale =
                                    double.tryParse(wholesaleCtrl.text) ?? 0;
                                final stock = double.tryParse(stockCtrl.text) ?? 0;
                                final cost = double.tryParse(costCtrl.text) ?? 0;
                                final discount =
                                    double.tryParse(discountCtrl.text) ?? 0;
                                final reorder =
                                    int.tryParse(reorderCtrl.text.trim()) ?? 0;
                                final size = sizeCtrl.text.trim();
                                final color = colorCtrl.text.trim();
                                final sku = skuCtrl.text.trim();

                                if (price <= 0) {
                                  AppFeedback.error(ctx, 'Retail price must be greater than 0.');
                                  return;
                                }
                                if (size.isEmpty && color.isEmpty) {
                                  AppFeedback.error(ctx, 'Set at least a size or a color.');
                                  return;
                                }
                                if (sku.isEmpty) {
                                  AppFeedback.error(ctx, 'SKU is required.');
                                  return;
                                }
                                if (wholesale < 0 || cost < 0 || stock < 0 || discount < 0) {
                                  AppFeedback.error(
                                    ctx,
                                    'Price, cost, stock, and discount values cannot be negative.',
                                  );
                                  return;
                                }
                                if (stock > 0 && cost <= 0) {
                                  AppFeedback.error(
                                    ctx,
                                    'Opening stock requires a cost price greater than 0.',
                                  );
                                  return;
                                }
                                if (reorder < 0) {
                                  AppFeedback.error(ctx, 'Reorder level cannot be negative.');
                                  return;
                                }
                                if (discountType == 'percentage' && discount > 100) {
                                  AppFeedback.error(
                                    ctx,
                                    'Percentage discount cannot exceed 100%.',
                                  );
                                  return;
                                }
                                if (discountType == 'fixed' && discount > price) {
                                  AppFeedback.error(
                                    ctx,
                                    'Fixed discount cannot exceed the retail price.',
                                  );
                                  return;
                                }

                                setSt(() => saving = true);
                                try {
                                  final created = await _service.addVariant(
                                    widget.groupId,
                                    VariantInput(
                                      size: size,
                                      color: color,
                                      secondaryName: secondaryNameCtrl.text.trim(),
                                      sku: sku,
                                      barcode: barcodeCtrl.text.trim(),
                                      price: price,
                                      wholesalePrice: wholesale,
                                      costPrice: cost,
                                      stock: stock,
                                      reorderLevel: reorder,
                                      discount: discount,
                                      discountType: discountType,
                                    ),
                                  );

                                  var imageFailed = false;
                                  if (imagePath != null && imagePath!.isNotEmpty) {
                                    final productId = int.tryParse(created['id']?.toString() ?? '');
                                    if (productId == null) {
                                      imageFailed = true;
                                    } else {
                                      try {
                                        await _productService.updateProduct(
                                          productId,
                                          const <String, dynamic>{},
                                          imagePath: imagePath,
                                        );
                                      } catch (e) {
                                        debugPrint('Variant image upload failed: $e');
                                        imageFailed = true;
                                      }
                                    }
                                  }

                                  if (!ctx.mounted) return;
                                  if (imageFailed) {
                                    AppFeedback.warning(
                                      ctx,
                                      'Variant was added, but its image could not be uploaded. Retry the image from Edit Variant.',
                                    );
                                  }
                                  Navigator.pop(ctx, true);
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setSt(() => saving = false);
                                    AppFeedback.error(ctx, 'Failed to add variant: $e');
                                  }
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add_rounded, size: 16),
                        label: const Text(
                          'Add Variant',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          minimumSize: const Size(120, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      sizeCtrl.dispose();
      colorCtrl.dispose();
      secondaryNameCtrl.dispose();
      priceCtrl.dispose();
      costCtrl.dispose();
      stockCtrl.dispose();
      wholesaleCtrl.dispose();
      discountCtrl.dispose();
      skuCtrl.dispose();
      barcodeCtrl.dispose();
      reorderCtrl.dispose();
    });

    return result;
  }

  // ── Edit Variant dialog ───────────────────────────────────────────────────

  Future<void> _editVariant(Map<String, dynamic> variant) async {
    final priceCtrl = TextEditingController(
        text: (variant['price'] ?? '').toString());
    final wholesaleCtrl = TextEditingController(
        text: (variant['wholesale_price'] ?? '').toString());
    final costCtrl = TextEditingController(
        text: (variant['cost_price'] ?? '').toString());
    final discountCtrl = TextEditingController(
        text: (variant['discount'] ?? 0).toString());
    final secondaryNameCtrl = TextEditingController(
        text: (variant['secondary_name'] ?? '').toString());
    final skuCtrl =
        TextEditingController(text: (variant['sku'] ?? '').toString());
    final barcodeCtrl = TextEditingController(
        text: (variant['barcode'] ?? '').toString());
    final reorderCtrl = TextEditingController(
        text: (variant['reorder_level'] ?? '').toString());

    double? currentStock;
    final stocks = variant['stocks'];
    if (stocks is List && stocks.isNotEmpty) {
      currentStock = double.tryParse(stocks.first['quantity']?.toString() ?? '');
    }
    final avgCostRaw = variant['avg_cost'] ?? variant['cost_price'];
    final avgCost =
        avgCostRaw != null ? double.tryParse(avgCostRaw.toString()) : null;

    final productId = int.tryParse(variant['id']?.toString() ?? '');
    if (productId == null || productId <= 0) {
      if (mounted) {
        AppFeedback.error(context, 'This variant has an invalid product ID.');
      }
      return;
    }

    final variantName = variant['name']?.toString() ?? '';
    final size = (variant['variant_size'] ?? '').toString();
    final color = (variant['variant_color'] ?? '').toString();
    final groupName = _group?['name']?.toString() ?? widget.groupName;
    final currentImageUrl = variant['image_url']?.toString();

    String discountType =
        variant['discount_type']?.toString().toLowerCase() == 'fixed'
            ? 'fixed'
            : 'percentage';
    String? pickedImagePath;
    bool removeCurrentImage = false;
    bool skuBusy = false;
    bool barcodeBusy = false;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
                  decoration: const BoxDecoration(
                    color: AppTheme.surfaceSoft,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.edit_outlined,
                            size: 18, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Edit Variant',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.navy)),
                            Text(variantName,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textMuted,
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (size.isNotEmpty || color.isNotEmpty) ...[
                        if (size.isNotEmpty)
                          _dimPill(Icons.straighten_rounded, size),
                        if (size.isNotEmpty && color.isNotEmpty)
                          const SizedBox(width: 4),
                        if (color.isNotEmpty)
                          _dimPill(Icons.palette_rounded, color),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppTheme.textMuted, size: 18),
                        onPressed:
                            saving ? null : () => Navigator.pop(ctx, false),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        splashRadius: 16,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: const BoxDecoration(
                    color: AppTheme.surfaceSoft,
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      _infoBadge(
                        'Current Stock',
                        currentStock != null ? _fmtQty(currentStock) : '—',
                        Icons.inventory_2_rounded,
                        color: currentStock == null
                            ? AppTheme.textMuted
                            : currentStock <= 0
                                ? AppTheme.danger
                                : AppTheme.success,
                      ),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 36, color: AppTheme.border),
                      const SizedBox(width: 8),
                      _infoBadge(
                        'Avg Cost',
                        avgCost != null ? AppCurrency.format(avgCost) : '—',
                        Icons.price_change_rounded,
                        color: AppTheme.textMuted,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppTheme.primary.withOpacity(0.4)),
                        ),
                        child: const Text('Stock Read Only',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                                letterSpacing: 0.3)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _dlgLabel('Product Image'),
                        const SizedBox(height: 8),
                        _variantImageEditor(
                          pickedPath: pickedImagePath,
                          currentUrl: currentImageUrl,
                          removeCurrent: removeCurrentImage,
                          onPick: saving
                              ? null
                              : () async {
                                  final path = await _pickVariantImage(ctx);
                                  if (path != null && ctx.mounted) {
                                    setSt(() {
                                      pickedImagePath = path;
                                      removeCurrentImage = false;
                                    });
                                  }
                                },
                          onRemove: saving
                              ? null
                              : () {
                                  setSt(() {
                                    pickedImagePath = null;
                                    removeCurrentImage = currentImageUrl != null &&
                                        currentImageUrl.isNotEmpty;
                                  });
                                },
                        ),
                        const SizedBox(height: 18),
                        _dlgLabel('Pricing'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _dlgField(priceCtrl, 'Retail Price *',
                                  numeric: true, required: true),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _dlgField(
                                  wholesaleCtrl, 'Wholesale Price',
                                  numeric: true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _dlgField(costCtrl, 'Reference Cost',
                                  numeric: true),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _dlgField(
                                discountCtrl,
                                discountType == 'fixed'
                                    ? 'Discount (Fixed Amount)'
                                    : 'Discount (%)',
                                numeric: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: discountType,
                          decoration: const InputDecoration(
                            labelText: 'Discount Type',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'percentage',
                              child: Text('Percentage (%)'),
                            ),
                            DropdownMenuItem(
                              value: 'fixed',
                              child: Text('Fixed Amount'),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setSt(() => discountType = value);
                                  }
                                },
                        ),
                        const SizedBox(height: 10),
                        _dlgField(secondaryNameCtrl, 'Secondary Name'),
                        const SizedBox(height: 18),
                        _dlgLabel('Identification'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                                child: _dlgField(skuCtrl, 'SKU *', required: true)),
                            const SizedBox(width: 8),
                            _genBtn(
                              label: 'Auto SKU',
                              icon: Icons.auto_awesome_rounded,
                              busy: skuBusy,
                              onTap: saving
                                  ? null
                                  : () async {
                                      setSt(() => skuBusy = true);
                                      try {
                                        final sku = await _service.generateSKU(
                                          groupName: groupName,
                                          size: size,
                                          color: color,
                                        );
                                        if (ctx.mounted) skuCtrl.text = sku;
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          AppFeedback.error(ctx,
                                              'SKU generation failed: $e');
                                        }
                                      } finally {
                                        if (ctx.mounted) {
                                          setSt(() => skuBusy = false);
                                        }
                                      }
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _dlgField(barcodeCtrl, 'Barcode')),
                            const SizedBox(width: 8),
                            _genBtn(
                              label: 'Auto',
                              icon: Icons.qr_code_2_rounded,
                              busy: barcodeBusy,
                              onTap: saving
                                  ? null
                                  : () async {
                                      setSt(() => barcodeBusy = true);
                                      try {
                                        final barcode =
                                            await _service.generateBarcode();
                                        if (ctx.mounted) barcodeCtrl.text = barcode;
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          AppFeedback.error(ctx,
                                              'Barcode generation failed: $e');
                                        }
                                      } finally {
                                        if (ctx.mounted) {
                                          setSt(() => barcodeBusy = false);
                                        }
                                      }
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _dlgField(reorderCtrl, 'Reorder Level', numeric: true),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          foregroundColor: AppTheme.textMuted,
                          minimumSize: const Size(90, 40),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final price = double.tryParse(priceCtrl.text);
                                final wholesale = double.tryParse(
                                        wholesaleCtrl.text.trim().isEmpty
                                            ? '0'
                                            : wholesaleCtrl.text.trim()) ??
                                    -1;
                                final cost = double.tryParse(
                                        costCtrl.text.trim().isEmpty
                                            ? '0'
                                            : costCtrl.text.trim()) ??
                                    -1;
                                final discount = double.tryParse(
                                        discountCtrl.text.trim().isEmpty
                                            ? '0'
                                            : discountCtrl.text.trim()) ??
                                    -1;
                                final reorder = double.tryParse(
                                        reorderCtrl.text.trim().isEmpty
                                            ? '0'
                                            : reorderCtrl.text.trim()) ??
                                    -1;

                                if (price == null || price <= 0) {
                                  AppFeedback.error(ctx,
                                      'Retail price must be greater than 0.');
                                  return;
                                }
                                if (skuCtrl.text.trim().isEmpty) {
                                  AppFeedback.error(ctx, 'SKU is required.');
                                  return;
                                }
                                if (wholesale < 0) {
                                  AppFeedback.error(ctx,
                                      'Wholesale price cannot be negative.');
                                  return;
                                }
                                if (cost < 0) {
                                  AppFeedback.error(
                                      ctx, 'Reference cost cannot be negative.');
                                  return;
                                }
                                if (discount < 0) {
                                  AppFeedback.error(
                                      ctx, 'Discount cannot be negative.');
                                  return;
                                }
                                if (discountType == 'percentage' &&
                                    discount > 100) {
                                  AppFeedback.error(ctx,
                                      'Percentage discount cannot exceed 100%.');
                                  return;
                                }
                                if (discountType == 'fixed' &&
                                    discount > price) {
                                  AppFeedback.error(ctx,
                                      'Fixed discount cannot exceed the retail price.');
                                  return;
                                }
                                if (reorder < 0) {
                                  AppFeedback.error(ctx,
                                      'Reorder level cannot be negative.');
                                  return;
                                }

                                setSt(() => saving = true);
                                try {
                                  await _service.updateVariant(
                                    widget.groupId,
                                    productId,
                                    <String, dynamic>{
                                      'price': price,
                                      'wholesale_price': wholesale,
                                      'cost_price': cost,
                                      'discount': discount,
                                      'discount_type': discountType,
                                      'secondary_name':
                                          secondaryNameCtrl.text.trim(),
                                      'sku': skuCtrl.text.trim(),
                                      'barcode': barcodeCtrl.text.trim(),
                                      'reorder_level': reorder,
                                    },
                                  );

                                  String? imageError;
                                  if (pickedImagePath != null ||
                                      removeCurrentImage) {
                                    try {
                                      await _productService.updateProduct(
                                        productId,
                                        const <String, dynamic>{},
                                        imagePath: pickedImagePath,
                                        removeImage: removeCurrentImage,
                                      );
                                    } catch (e) {
                                      imageError = e.toString();
                                    }
                                  }

                                  if (!ctx.mounted) return;
                                  if (imageError != null) {
                                    AppFeedback.warning(
                                      ctx,
                                      'Variant changes were saved, but the image could not be updated. '
                                      'Open Edit Variant and retry the image. ($imageError)',
                                    );
                                  } else {
                                    AppFeedback.success(
                                        ctx, 'Variant updated successfully.');
                                  }
                                  Navigator.pop(ctx, true);
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setSt(() => saving = false);
                                    AppFeedback.error(
                                        ctx, 'Failed to save variant: $e');
                                  }
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_rounded, size: 17),
                        label: Text(saving ? 'Saving...' : 'Save Changes',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          minimumSize: const Size(118, 40),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true && mounted) {
      _changed = true;
      _load();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      priceCtrl.dispose();
      wholesaleCtrl.dispose();
      costCtrl.dispose();
      discountCtrl.dispose();
      secondaryNameCtrl.dispose();
      skuCtrl.dispose();
      barcodeCtrl.dispose();
      reorderCtrl.dispose();
    });
  }

  Future<void> _toggleVariantActive(Map<String, dynamic> variant) async {
    final id = variant['id'] as int;
    final newActive =
        !(variant['is_active'] == 1 || variant['is_active'] == true);
    try {
      await _service.updateVariant(
          widget.groupId, id, {'is_active': newActive});
      _changed = true;
      _load();
    } catch (e) {
      if (mounted)
        AppFeedback.error(context, 'Failed to update variant: $e');
    }
  }

  Future<void> _removeVariant(Map<String, dynamic> variant) async {
    final name = variant['name']?.toString() ?? 'this variant';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        size: 20, color: AppTheme.danger),
                  ),
                  const SizedBox(width: 12),
                  const Text('Remove Variant',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy)),
                ],
              ),
              const SizedBox(height: 14),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.navy,
                      height: 1.5),
                  children: [
                    const TextSpan(text: 'Remove '),
                    TextSpan(
                        text: '"$name"',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                    const TextSpan(
                        text:
                            '? This is only allowed when the variant has no stock movement history.'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.border),
                      foregroundColor: AppTheme.textMuted,
                      minimumSize: const Size(80, 38),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      minimumSize: const Size(100, 38),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_rounded, size: 15),
                    label: const Text('Remove',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await _service.removeVariant(widget.groupId, variant['id'] as int);
      _changed = true;
      _load();
      if (mounted) AppFeedback.success(context, 'Variant removed.');
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'Failed to remove: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  double _variantStock(Map<String, dynamic> variant) {
    final stocks = variant['stocks'];
    if (stocks is! List) return 0;
    return stocks.fold<double>(0, (sum, row) {
      if (row is! Map) return sum;
      return sum + _dbl(row['quantity']);
    });
  }

  double get _totalStock =>
      _variants.fold<double>(0, (sum, variant) => sum + _variantStock(variant));

  String get _priceRangeLabel {
    if (_variants.isEmpty) return '—';
    final prices = _variants
        .map((v) => _dbl(v['price']))
        .where((v) => v >= 0)
        .toList();
    if (prices.isEmpty) return '—';
    prices.sort();
    final min = prices.first;
    final max = prices.last;
    if ((max - min).abs() < 0.0001) return AppCurrency.format(min);
    return '${AppCurrency.format(min)} – ${AppCurrency.format(max)}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final canManage = auth.hasPermission('manage-products');
    final canPrintBarcodes = auth.hasPermission('print-barcode-labels') &&
        auth.hasAddon('barcode_labels');

    final groupName = _group?['name']?.toString() ?? widget.groupName;
    final isActive =
        _group?['is_active'] == 1 || _group?['is_active'] == true;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: EnterprisePage(
        title: groupName,
        subtitle: _loading
            ? 'Loading variable product details…'
            : 'Variable product • ${_variants.length} variant${_variants.length == 1 ? '' : 's'} • ${isActive ? 'Active' : 'Inactive'}',
        icon: Icons.style_rounded,
        actions: [
          if (canPrintBarcodes && !_loading && _variants.isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed: _printGroupBarcodes,
              icon: const Icon(Icons.qr_code_2_rounded, size: 17),
              label: const Text('Print Barcodes'),
            ),
            const SizedBox(width: 8),
          ],
          if (canManage && !_loading) ...[
            OutlinedButton.icon(
              onPressed: _editGroup,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit Product'),
            ),
            FilledButton.icon(
              onPressed: _addVariant,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Variant'),
            ),
          ],
        ],
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    if (_group != null) _buildGroupInfoCard(),
                    const SizedBox(height: 14),
                    _buildVariantsSection(canManage, canPrintBarcodes),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Group info card ───────────────────────────────────────────────────────

  Widget _buildGroupInfoCard() {
    final g = _group!;
    final isActive = g['is_active'] == 1 || g['is_active'] == true;
    final taxInclusive =
        g['tax_inclusive'] == 1 || g['tax_inclusive'] == true;

    final catName = (g['category_name'] ?? g['category']?['name'] ?? '—')
        .toString();
    final brandName =
        (g['brand_name'] ?? g['brand']?['name'] ?? '—').toString();
    final unitName =
        (g['unit_name'] ?? g['unit']?['name'] ?? '—').toString();
    final vendorName = (g['vendor_name'] ??
            '${g['vendor']?['first_name'] ?? ''} ${g['vendor']?['last_name'] ?? ''}'
                .trim())
        .toString();
    final safeVendor = vendorName.trim().isEmpty ? '—' : vendorName;
    final taxRate = _dbl(g['tax_rate']);
    final secondaryName = (g['secondary_name'] ?? '').toString().trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Product Family',
                        style: TextStyle(
                          color: AppTheme.navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Shared catalog information and live inventory summary.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                EnterpriseStatusBadge(
                  label: isActive ? 'ACTIVE' : 'INACTIVE',
                  color: isActive ? AppTheme.success : AppTheme.textMuted,
                  icon: isActive
                      ? Icons.check_circle_rounded
                      : Icons.pause_circle_outline_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                EnterpriseMetricChip(
                  label: 'Variants',
                  value: '${_variants.length}',
                  color: AppTheme.primary,
                  icon: Icons.view_module_rounded,
                ),
                EnterpriseMetricChip(
                  label: 'Total Stock',
                  value: _fmtQty(_totalStock),
                  color: _totalStock <= 0
                      ? AppTheme.danger
                      : _totalStock <= 5
                          ? AppTheme.warning
                          : AppTheme.success,
                  icon: Icons.inventory_rounded,
                ),
                EnterpriseMetricChip(
                  label: 'Price',
                  value: _priceRangeLabel,
                  color: AppTheme.info,
                  icon: Icons.sell_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final itemWidth = compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    if (secondaryName.isNotEmpty)
                      SizedBox(
                        width: itemWidth,
                        child: _metadataItem(
                          Icons.translate_rounded,
                          'Secondary Name',
                          secondaryName,
                        ),
                      ),
                    SizedBox(
                      width: itemWidth,
                      child: _metadataItem(
                          Icons.category_outlined, 'Category', catName),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _metadataItem(Icons.branding_watermark_outlined,
                          'Brand', brandName),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _metadataItem(
                          Icons.straighten_outlined, 'Unit', unitName),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _metadataItem(
                          Icons.storefront_outlined, 'Vendor', safeVendor),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _metadataItem(
                        Icons.percent_rounded,
                        'Tax Rate',
                        '${taxRate.toStringAsFixed(taxRate % 1 == 0 ? 0 : 2)}%',
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _metadataItem(
                        Icons.receipt_long_outlined,
                        'Tax Pricing',
                        taxInclusive ? 'Inclusive' : 'Exclusive',
                        valueColor: taxInclusive
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadataItem(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft.withOpacity(.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppTheme.border),
            ),
            child: Icon(icon, size: 15, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: valueColor ?? AppTheme.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Variants section ──────────────────────────────────────────────────────

  Widget _buildVariantsSection(bool canManage, bool canPrintBarcodes) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.tune_rounded,
                      size: 19, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Variants',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.navy,
                            ),
                          ),
                          const SizedBox(width: 8),
                          EnterpriseStatusBadge(
                            label: '${_variants.length}',
                            color: AppTheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Each row is a real SKU with independent stock, price and carrying cost.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  FilledButton.icon(
                    onPressed: _addVariant,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Add Variant'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          if (_variants.isEmpty)
            _buildEmptyVariants(canManage)
          else
            _buildVariantTable(canManage, canPrintBarcodes),
        ],
      ),
    );
  }

  Widget _buildEmptyVariants(bool canManage) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      child: EnterpriseEmptyState(
        icon: Icons.view_module_outlined,
        title: 'No variants yet',
        subtitle: 'Add the first size or color combination for this product family.',
        action: canManage
            ? FilledButton.icon(
                onPressed: _addVariant,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Add First Variant'),
              )
            : null,
      ),
    );
  }

  // ── Variant table ─────────────────────────────────────────────────────────

  Widget _buildVariantTable(bool canManage, bool canPrintBarcodes) {
    final hasSize = _variants
        .any((v) => (v['variant_size'] ?? '').toString().isNotEmpty);
    final hasColor = _variants
        .any((v) => (v['variant_color'] ?? '').toString().isNotEmpty);
    final hasSku =
        _variants.any((v) => (v['sku'] ?? '').toString().isNotEmpty);
    final hasBarcode =
        _variants.any((v) => (v['barcode'] ?? '').toString().isNotEmpty);

    const hStyle = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
        color: AppTheme.textMuted,
        letterSpacing: 0.55);

    Widget hdr(String label, {bool right = false}) => Padding(
          padding: EdgeInsets.fromLTRB(
              right ? 4 : 14, 11, right ? 14 : 4, 11),
          child: Text(label,
              style: hStyle,
              textAlign: right ? TextAlign.right : TextAlign.left),
        );

    Widget cell(
      String text, {
      bool right = false,
      TextStyle? style,
    }) =>
        Padding(
          padding:
              EdgeInsets.fromLTRB(right ? 4 : 12, 12, right ? 12 : 4, 12),
          child: Text(
            text,
            style: style ??
                const TextStyle(fontSize: 12.5, color: AppTheme.navy),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: right ? TextAlign.right : TextAlign.left,
          ),
        );

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            horizontalInside: BorderSide(
                color: AppTheme.border.withOpacity(0.6), width: 0.5),
          ),
          children: [
            // ── Header ────────────────────────────────────────────────────
            TableRow(
              decoration: const BoxDecoration(
                color: AppTheme.surfaceSoft,
                border: Border(
                  bottom: BorderSide(color: AppTheme.borderStrong),
                ),
              ),
              children: [
                hdr('IMAGE'),
                if (hasSize) hdr('SIZE'),
                if (hasColor) hdr('COLOR'),
                if (hasSku) hdr('SKU'),
                if (hasBarcode) hdr('BARCODE'),
                hdr('STOCK', right: true),
                hdr('AVG COST', right: true),
                hdr('RETAIL', right: true),
                hdr('WHOLESALE', right: true),
                hdr('DISCOUNT', right: true),
                hdr('STATUS'),
                if (canManage || canPrintBarcodes) hdr(''),
              ],
            ),
            // ── Data rows ─────────────────────────────────────────────────
            ..._variants.asMap().entries.map((entry) {
              final idx = entry.key;
              final v = entry.value;
              final isActive =
                  v['is_active'] == 1 || v['is_active'] == true;

              double? stock;
              final stocks = v['stocks'];
              if (stocks is List && stocks.isNotEmpty) {
                stock = double.tryParse(
                    stocks.first['quantity']?.toString() ?? '');
              }
              final avgCostRaw = v['avg_cost'] ?? v['cost_price'];
              final avgCost = avgCostRaw != null
                  ? double.tryParse(avgCostRaw.toString())
                  : null;

              final stockColor = stock == null
                  ? AppTheme.textMuted
                  : stock <= 0
                      ? AppTheme.danger
                      : AppTheme.success;

              final dimStyle = TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color:
                      isActive ? AppTheme.navy : AppTheme.textMuted);

              final mutedStyle = const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  fontFamily: 'monospace');

              // Subtle row stripe
              final rowBg = idx.isEven
                  ? Colors.white
                  : const Color(0xFFFAFBFF);

              return TableRow(
                decoration: BoxDecoration(
                    color: isActive
                        ? rowBg
                        : AppTheme.surfaceSoft.withOpacity(0.4)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: _variantTableThumbnail(v['image_url']?.toString()),
                  ),
                  if (hasSize)
                    cell(
                      (v['variant_size'] ?? '').toString().isEmpty
                          ? '—'
                          : v['variant_size'].toString(),
                      style: dimStyle,
                    ),
                  if (hasColor)
                    cell(
                      (v['variant_color'] ?? '').toString().isEmpty
                          ? '—'
                          : v['variant_color'].toString(),
                      style: dimStyle,
                    ),
                  if (hasSku)
                    cell((v['sku'] ?? '—').toString(),
                        style: mutedStyle),
                  if (hasBarcode)
                    cell((v['barcode'] ?? '—').toString(),
                        style: mutedStyle),
                  // Stock
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 11, 14, 11),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: stockColor.withOpacity(0.09),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: stockColor.withOpacity(0.35)),
                          boxShadow: [
                            BoxShadow(
                              color: stockColor.withOpacity(0.12),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          stock != null ? _fmtQty(stock) : '—',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: stockColor),
                        ),
                      ),
                    ),
                  ),
                  cell(
                    avgCost != null ? AppCurrency.format(avgCost) : '—',
                    right: true,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                  ),
                  cell(
                    AppCurrency.format(_dbl(v['price'])),
                    right: true,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy),
                  ),
                  cell(
                    v['wholesale_price'] != null &&
                            _dbl(v['wholesale_price']) > 0
                        ? AppCurrency.format(_dbl(v['wholesale_price']))
                        : '—',
                    right: true,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                  ),
                  cell(
                    _variantDiscountLabel(v),
                    right: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _dbl(v['discount']) > 0
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _dbl(v['discount']) > 0
                          ? AppTheme.primary
                          : AppTheme.textMuted,
                    ),
                  ),
                  // Status
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppTheme.success.withOpacity(0.08)
                            : AppTheme.textMuted.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isActive
                              ? AppTheme.success.withOpacity(0.3)
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppTheme.success
                                  : AppTheme.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? AppTheme.success
                                    : AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (canManage || canPrintBarcodes)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canPrintBarcodes)
                            IconButton(
                              tooltip: 'Print this variant barcode',
                              onPressed: () => _printOneVariant(v),
                              icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                              color: AppTheme.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (canManage)
                            IconButton(
                              tooltip: 'Edit variant',
                              onPressed: () => _editVariant(v),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              color: AppTheme.primary,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (canManage)
                            PopupMenuButton<String>(
                            tooltip: 'More actions',
                            onSelected: (action) {
                              if (action == 'toggle') _toggleVariantActive(v);
                              if (action == 'delete') _removeVariant(v);
                            },
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            position: PopupMenuPosition.under,
                            itemBuilder: (_) => [
                              _menuItem(
                                  'toggle',
                                  isActive
                                      ? Icons.block_rounded
                                      : Icons.check_circle_rounded,
                                  isActive ? 'Deactivate' : 'Activate',
                                  isActive
                                      ? AppTheme.textMuted
                                      : AppTheme.success),
                              _menuItem(
                                  'delete',
                                  Icons.delete_outline_rounded,
                                  'Remove',
                                  AppTheme.danger),
                            ],
                            icon: const Icon(Icons.more_horiz_rounded,
                                size: 18, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _variantTableThumbnail(String? imageUrl) {
    final url = imageUrl?.trim() ?? '';
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? const Icon(Icons.image_outlined,
              size: 18, color: AppTheme.textMuted)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: AppTheme.textMuted),
            ),
    );
  }

  String _variantDiscountLabel(Map<String, dynamic> variant) {
    final discount = _dbl(variant['discount']);
    if (discount <= 0) return '—';
    final type = variant['discount_type']?.toString().toLowerCase();
    if (type == 'fixed') return AppCurrency.format(discount);
    final formatted = discount == discount.roundToDouble()
        ? discount.toInt().toString()
        : discount.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$formatted%';
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  // ── Dialog helpers ────────────────────────────────────────────────────────

  Widget _dlgLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.textMuted,
                letterSpacing: 0.6)),
      );

  TextField _dlgField(
    TextEditingController ctrl,
    String hint, {
    bool numeric = false,
    bool required = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: required
                    ? AppTheme.primary.withOpacity(0.4)
                    : AppTheme.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _genBtn({
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      icon: busy
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppTheme.primary))
          : Icon(icon, size: 13),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        side: const BorderSide(color: AppTheme.primary),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _dimPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.navy,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _infoBadge(String label, String value, IconData icon,
      {required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.textMuted)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ],
        ),
      ],
    );
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  String _fmtQty(double qty) {
    return qty == qty.truncateToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
  }

  double _dbl(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
