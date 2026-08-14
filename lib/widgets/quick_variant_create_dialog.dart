import 'dart:typed_data';

import 'package:enterprise_pos/api/product_group_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QuickVariantCreateResult {
  final Map<String, dynamic> product;
  final bool imageUploadFailed;

  const QuickVariantCreateResult({
    required this.product,
    this.imageUploadFailed = false,
  });
}

class QuickVariantCreateDialog extends StatefulWidget {
  final int groupId;
  final String groupName;
  final bool purchaseMode;
  final String token;

  const QuickVariantCreateDialog({
    required this.groupId,
    required this.groupName,
    required this.purchaseMode,
    required this.token,
  });

  @override
  State<QuickVariantCreateDialog> createState() =>
      _QuickVariantCreateDialogState();
}

class _QuickVariantCreateDialogState
    extends State<QuickVariantCreateDialog> {
  final _sizeCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _secondaryNameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _retailCtrl = TextEditingController();
  final _wholesaleCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _reorderCtrl = TextEditingController(text: '0');
  final _stockCtrl = TextEditingController(text: '0');

  String _discountType = 'percentage';
  String? _imagePath;
  String? _imageName;
  Uint8List? _imageBytes;
  bool _skuBusy = false;
  bool _barcodeBusy = false;
  bool _saving = false;

  late final ProductGroupService _groupService;
  late final ProductService _productService;

  @override
  void initState() {
    super.initState();
    _groupService = ProductGroupService(token: widget.token);
    _productService = ProductService(token: widget.token);
  }

  @override
  void dispose() {
    for (final ctrl in <TextEditingController>[
      _sizeCtrl,
      _colorCtrl,
      _secondaryNameCtrl,
      _skuCtrl,
      _barcodeCtrl,
      _retailCtrl,
      _wholesaleCtrl,
      _costCtrl,
      _discountCtrl,
      _reorderCtrl,
      _stockCtrl,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  bool get _isPurchase => widget.purchaseMode;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.single.path == null) return;
    final file = result.files.single;
    if (file.size > 2 * 1024 * 1024) {
      if (mounted) {
        AppFeedback.error(context, 'Product images must be 2 MB or smaller.');
      }
      return;
    }
    setState(() {
      _imagePath = file.path;
      _imageName = file.name;
      _imageBytes = file.bytes;
    });
  }

  Future<void> _generateSku() async {
    setState(() => _skuBusy = true);
    try {
      final sku = await _groupService.generateSKU(
        groupName: widget.groupName,
        size: _sizeCtrl.text.trim(),
        color: _colorCtrl.text.trim(),
      );
      if (mounted) _skuCtrl.text = sku;
    } catch (e) {
      if (mounted) AppFeedback.error(context, 'SKU generation failed: $e');
    } finally {
      if (mounted) setState(() => _skuBusy = false);
    }
  }

  Future<void> _generateBarcode() async {
    setState(() => _barcodeBusy = true);
    try {
      final barcode = await _groupService.generateBarcode();
      if (mounted) _barcodeCtrl.text = barcode;
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, 'Barcode generation failed: $e');
      }
    } finally {
      if (mounted) setState(() => _barcodeBusy = false);
    }
  }

  Future<void> _save() async {
    final size = _sizeCtrl.text.trim();
    final color = _colorCtrl.text.trim();
    final sku = _skuCtrl.text.trim();
    final retail = double.tryParse(_retailCtrl.text.trim()) ?? 0;
    final wholesale = double.tryParse(_wholesaleCtrl.text.trim()) ?? 0;
    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0;
    final discount = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    final reorder = int.tryParse(_reorderCtrl.text.trim()) ?? 0;
    final stock = _isPurchase
        ? 0.0
        : (double.tryParse(_stockCtrl.text.trim()) ?? 0);

    if (size.isEmpty && color.isEmpty) {
      AppFeedback.error(context, 'Set at least a size or a color.');
      return;
    }
    if (retail <= 0) {
      AppFeedback.error(context, 'Retail price must be greater than 0.');
      return;
    }
    if (sku.isEmpty) {
      AppFeedback.error(context, 'SKU is required.');
      return;
    }
    if (wholesale < 0 || cost < 0 || discount < 0 || stock < 0) {
      AppFeedback.error(
        context,
        'Price, cost, discount, and stock values cannot be negative.',
      );
      return;
    }
    if (stock > 0 && cost <= 0) {
      AppFeedback.error(
        context,
        'Opening stock requires a cost price greater than 0.',
      );
      return;
    }
    if (reorder < 0) {
      AppFeedback.error(context, 'Reorder level cannot be negative.');
      return;
    }
    if (_discountType == 'percentage' && discount > 100) {
      AppFeedback.error(context, 'Percentage discount cannot exceed 100%.');
      return;
    }
    if (_discountType == 'fixed' && discount > retail) {
      AppFeedback.error(context, 'Fixed discount cannot exceed retail price.');
      return;
    }

    setState(() => _saving = true);
    try {
      var product = await _groupService.addVariant(
        widget.groupId,
        VariantInput(
          size: size,
          color: color,
          secondaryName: _secondaryNameCtrl.text.trim(),
          sku: sku,
          barcode: _barcodeCtrl.text.trim(),
          price: retail,
          wholesalePrice: wholesale,
          costPrice: cost,
          stock: stock,
          reorderLevel: reorder,
          discount: discount,
          discountType: _discountType,
        ),
      );

      var imageFailed = false;
      final productId = int.tryParse(product['id']?.toString() ?? '');
      if (_imagePath != null && _imagePath!.isNotEmpty) {
        if (productId == null || productId <= 0) {
          imageFailed = true;
        } else {
          try {
            final updated = await _productService.updateProduct(
              productId,
              const <String, dynamic>{},
              imagePath: _imagePath,
            );
            if (updated['id'] != null) {
              product = Map<String, dynamic>.from(updated);
            } else if (updated['product'] is Map) {
              product = Map<String, dynamic>.from(updated['product'] as Map);
            }
          } catch (e) {
            debugPrint('Quick variant image upload failed: $e');
            imageFailed = true;
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        QuickVariantCreateResult(
          product: Map<String, dynamic>.from(product),
          imageUploadFailed: imageFailed,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppFeedback.error(context, 'Failed to create variant: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _section('Variant'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _field(_sizeCtrl, 'Size')),
                        const SizedBox(width: 10),
                        Expanded(child: _field(_colorCtrl, 'Color')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _field(_secondaryNameCtrl, 'Secondary Name'),
                    const SizedBox(height: 16),
                    _section('Product Image'),
                    const SizedBox(height: 8),
                    _imagePicker(),
                    const SizedBox(height: 16),
                    _section('Pricing'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            _retailCtrl,
                            'Retail Price *',
                            numeric: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            _wholesaleCtrl,
                            'Wholesale Price',
                            numeric: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _field(_costCtrl, 'Cost Price', numeric: true),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            _discountCtrl,
                            _discountType == 'fixed'
                                ? 'Discount (Fixed)'
                                : 'Discount (%)',
                            numeric: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _discountType,
                      decoration: const InputDecoration(
                        labelText: 'Discount Type',
                        isDense: true,
                        border: OutlineInputBorder(),
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
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _discountType = value);
                              }
                            },
                    ),
                    const SizedBox(height: 16),
                    _section('Inventory'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            _reorderCtrl,
                            'Reorder Level',
                            numeric: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _isPurchase
                              ? _purchaseStockInfo()
                              : _field(
                                  _stockCtrl,
                                  'Opening Stock',
                                  numeric: true,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _section('Identification'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _field(_skuCtrl, 'SKU *')),
                        const SizedBox(width: 8),
                        _generateButton(
                          'Auto SKU',
                          Icons.auto_awesome_rounded,
                          _skuBusy,
                          _generateSku,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _field(_barcodeCtrl, 'Barcode')),
                        const SizedBox(width: 8),
                        _generateButton(
                          'Auto',
                          Icons.qr_code_2_rounded,
                          _barcodeBusy,
                          _generateBarcode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: AppTheme.primary),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Category, brand, unit, vendor and tax settings are inherited automatically from the product family.',
                              style: TextStyle(
                                color: AppTheme.primaryDark,
                                fontSize: 10.5,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 17, 12, 15),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_rounded,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick New Variant',
                  style: TextStyle(
                    color: AppTheme.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Create a permanent SKU inside ${widget.groupName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded,
                color: AppTheme.textMuted, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _imagePicker() {
    final hasImage = _imagePath != null && _imagePath!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.surfaceSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: hasImage && _imageBytes != null
                ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                : Icon(
                    hasImage ? Icons.image_rounded : Icons.image_outlined,
                    color: hasImage ? AppTheme.primary : AppTheme.textMuted,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasImage ? (_imageName ?? 'Selected image') : 'No image selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'JPG, PNG or WebP · maximum 2 MB',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (hasImage)
            IconButton(
              tooltip: 'Remove image',
              onPressed: _saving
                  ? null
                  : () => setState(() {
                        _imagePath = null;
                        _imageName = null;
                        _imageBytes = null;
                      }),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickImage,
            icon: const Icon(Icons.folder_open_rounded, size: 16),
            label: Text(hasImage ? 'Replace' : 'Choose'),
          ),
        ],
      ),
    );
  }

  Widget _purchaseStockInfo() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.primary.withOpacity(.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 16, color: AppTheme.primary),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'Opening stock = 0\nReceive through this purchase',
              style: TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 9.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_rounded, size: 17),
            label: const Text('Create & Add'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(130, 41),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: AppTheme.navy,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _generateButton(
    String label,
    IconData icon,
    bool busy,
    VoidCallback onTap,
  ) {
    return OutlinedButton.icon(
      onPressed: _saving || busy ? null : onTap,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 15),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size(88, 47)),
    );
  }
}

