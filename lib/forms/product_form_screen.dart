import 'dart:io';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/unit_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/screens/units_screen.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/vendor_picker_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ProductFormScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  final int? vendorId;

  const ProductFormScreen({super.key, this.product, this.vendorId});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // text controllers
  final _skuController            = TextEditingController();
  final _barcodeController        = TextEditingController();
  final _nameController           = TextEditingController();
  final _descController           = TextEditingController();
  final _priceController          = TextEditingController();
  final _stockController          = TextEditingController();
  final _costPriceController      = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  final _taxRateController        = TextEditingController();
  final _discountController       = TextEditingController();

  bool _isActive          = true;
  bool _taxInclusive      = false;
  bool _loading           = false;
  bool _skuGenerating     = false;
  bool _barcodeGenerating = false;
  String _discountType = 'percentage'; // 'percentage' | 'fixed'

  int? _selectedCategoryId;
  int? _selectedBrandId;

  Map<String, dynamic>? _selectedVendor;
  int?                  _selectedVendorId;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _brands     = [];

  /// Unit of measure. Drives whether the till accepts a decimal quantity for
  /// this product — see QuantityRule.
  int?               _selectedUnitId;
  List<ProductUnit>  _units = [];
  late String        _token;
  late UnitService   _unitService;

  // ── Image state ──────────────────────────────────────────────────────────────
  /// File picked from disk, not yet uploaded.
  File?   _pickedImageFile;
  /// Existing image URL already saved on the server (shown on edit).
  String? _currentImageUrl;
  /// True when the user explicitly removed the current image and no new one
  /// is queued — tells the backend to null the column.
  bool _removeImage = false;
  // ─────────────────────────────────────────────────────────────────────────────

  late ProductService _productService;
  late CommonService  _commonService;

  bool get _isEdit => widget.product != null;

  /// True when this product belongs to a variable-product group.
  bool get _isVariantProduct =>
      widget.product != null &&
      widget.product!['product_group_id'] != null;

  Widget _buildVariantBadge() {
    final p = widget.product!;
    final size = p['variant_size']?.toString() ?? '';
    final color = p['variant_color']?.toString() ?? '';
    final dims = [if (size.isNotEmpty) size, if (color.isNotEmpty) color];
    final label = dims.isEmpty ? 'Variant product' : dims.join(' / ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded,
              size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Variant: $label  ·  Changes here affect this variant only.',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    _token          = token;
    _productService = ProductService(token: token);
    _commonService  = CommonService(token: token);
    _unitService    = UnitService(token: token);

    if (widget.product != null) {
      final p = widget.product!;
      _skuController.text            = p['sku']?.toString()     ?? '';
      _barcodeController.text        = p['barcode']?.toString() ?? '';
      _nameController.text           = p['name']            ?? '';
      _descController.text           = p['description']     ?? '';
      _priceController.text          = p['price']?.toString()           ?? '';
      _costPriceController.text      = p['cost_price']?.toString()      ?? '';
      _wholesalePriceController.text = p['wholesale_price']?.toString() ?? '';
      _taxRateController.text        = p['tax_rate']?.toString()        ?? '';
      _discountController.text       = p['discount']?.toString()        ?? '';
      _discountType = (p['discount_type'] ?? 'percentage').toString();
      _isActive     = p['is_active']    == 1 || p['is_active']    == true;
      _taxInclusive = p['tax_inclusive'] == 1 || p['tax_inclusive'] == true;
      _selectedCategoryId = p['category_id'];
      _selectedBrandId    = p['brand_id'];
      // unit_id is the flat column; fall back to the nested relation, which is
      // what /products actually returns.
      _selectedUnitId = p['unit_id'] is int
          ? p['unit_id'] as int
          : (p['unit'] is Map ? (p['unit']['id'] as num?)?.toInt() : null);

      // Existing server image
      _currentImageUrl = p['image_url']?.toString();

      _selectedVendorId = p['vendor_id'] is int ? p['vendor_id'] as int : null;
      if (p['vendor'] is Map<String, dynamic>) {
        _selectedVendor   = {'id': p['vendor']['id'], 'first_name': p['vendor']['first_name']};
        _selectedVendorId = _selectedVendor?['id'] as int?;
      }
    }

    if (widget.vendorId != null) {
      _selectedVendorId = widget.vendorId;
      _selectedVendor   = {'id': widget.vendorId, 'first_name': 'Vendor #${widget.vendorId}'};
    }

    _loadInitialData();
  }

  @override
  void dispose() {
    _skuController.dispose();
    _barcodeController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _costPriceController.dispose();
    _wholesalePriceController.dispose();
    _taxRateController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final cats   = await _commonService.getCategories();
      final brands = await _commonService.getBrands();
      setState(() {
        _categories = cats;
        _brands     = brands;
      });
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    }
    await _loadUnits();
  }

  /// Loads units separately from categories/brands so that a user WITHOUT the
  /// view-units permission still gets a working product form — they simply
  /// cannot change the unit. Folding this into _loadInitialData would let a
  /// 403 on /units wipe the category and brand lists too.
  Future<void> _loadUnits() async {
    try {
      final units = await _unitService.list();
      if (!mounted) return;
      setState(() {
        _units = units.where((u) => u.isActive || u.id == _selectedUnitId).toList();
        // Creating a product: default to the only unit, or to Piece, so the
        // field is never silently empty.
        if (_selectedUnitId == null && !_isEdit && _units.isNotEmpty) {
          final piece = _units.where((u) => u.name.toLowerCase() == 'piece');
          _selectedUnitId = piece.isNotEmpty ? piece.first.id : _units.first.id;
        }
      });
    } catch (e) {
      debugPrint('Error loading units: $e');
    }
  }

  Future<void> _autoSKU() async {
    setState(() => _skuGenerating = true);
    try {
      final sku = await _productService.generateSKU(
        productName: _nameController.text.trim(),
      );
      if (mounted) setState(() => _skuController.text = sku);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SKU generation failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _skuGenerating = false);
    }
  }

  Future<void> _autoBarcode() async {
    setState(() => _barcodeGenerating = true);
    try {
      final barcode = await _productService.generateBarcode();
      if (mounted) setState(() => _barcodeController.text = barcode);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Barcode generation failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _barcodeGenerating = false);
    }
  }

  // ── Image helpers ─────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedImageFile = File(result.files.single.path!);
        _removeImage     = false; // a fresh pick cancels any pending removal
      });
    }
  }

  void _clearImage() {
    setState(() {
      _pickedImageFile = null;
      // Flag removal only when there is an existing server image to delete.
      _removeImage = _currentImageUrl != null;
    });
  }

  Widget _buildImageSection() {
    final hasPickedFile  = _pickedImageFile != null;
    final hasServerImage = _currentImageUrl != null && !_removeImage && !hasPickedFile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Image',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),

        if (hasPickedFile) ...[
          // Preview of the locally picked file
          Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _pickedImageFile!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              _imageRemoveButton(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _pickedImageFile!.path.split(Platform.pathSeparator).last,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ] else if (hasServerImage) ...[
          // Current image saved on the server
          Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _currentImageUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : SizedBox(height: 160, child: const Center(child: CircularProgressIndicator())),
                  errorBuilder: (_, __, ___) => _imagePlaceholder(),
                ),
              ),
              _imageRemoveButton(),
            ],
          ),
        ] else ...[
          _imagePlaceholder(),
        ],

        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.image_outlined, size: 18),
          label: Text(hasPickedFile || hasServerImage ? 'Replace Image' : 'Pick Image'),
          onPressed: _pickImage,
        ),
      ],
    );
  }

  Widget _imageRemoveButton() {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: Colors.black54,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 16,
          tooltip: 'Remove image',
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _clearImage,
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 36),
            SizedBox(height: 6),
            Text('No image', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ── Vendor ────────────────────────────────────────────────────────────────────

  Future<void> _pickVendor() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: VendorPickerSheet(token: token),
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedVendor   = picked;
        _selectedVendorId = picked['id'] as int?;
      });
    }
  }

  Future<String?> _showAddDialog(String type) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $type'),
        content: TextField(controller: controller, decoration: InputDecoration(hintText: '$type Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final payload = <String, dynamic>{
      'sku':             _skuController.text,
      'barcode':         _barcodeController.text,
      'name':            _nameController.text,
      'description':     _descController.text,
      'stock':           double.tryParse(_stockController.text) ?? 0,
      'price':           double.tryParse(_priceController.text) ?? 0.0,
      'cost_price':      double.tryParse(_costPriceController.text) ?? 0.0,
      'wholesale_price': double.tryParse(_wholesalePriceController.text) ?? 0.0,
      'tax_rate':        double.tryParse(_taxRateController.text) ?? 0.0,
      'tax_inclusive':   _taxInclusive,
      'discount':        double.tryParse(_discountController.text) ?? 0.0,
      'discount_type':   _discountType,
      'category_id':     _selectedCategoryId,
      'brand_id':        _selectedBrandId,
      'unit_id':         _selectedUnitId,
      'vendor_id':       _selectedVendorId,
      'is_active':       _isActive,
      'branch_stocks':   <Map<String, dynamic>>[],
    };

    try {
      if (!_isEdit) {
        final product = await _productService.createProduct(
          payload,
          imagePath: _pickedImageFile?.path,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product created successfully')),
        );
        Navigator.pop(context, product);
      } else {
        await _productService.updateProduct(
          widget.product!['id'] as int,
          payload,
          imagePath:   _pickedImageFile?.path,
          removeImage: _removeImage,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fixedVendorId      = widget.vendorId;
    final productVendorId    = widget.product?['vendor_id'];
    final showReadOnlyVendor = _isEdit || fixedVendorId != null;
    final effectiveVendorId  = fixedVendorId ?? productVendorId ?? _selectedVendorId;
    final effectiveVendorName =
        _selectedVendor?['first_name']?.toString() ??
        widget.product?['vendor']?['first_name'] ??
        (effectiveVendorId != null ? 'Vendor #$effectiveVendorId' : 'None selected');

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Product' : 'Add Product')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Variant badge (read-only, shown when editing a variant) ─────
              if (_isEdit && _isVariantProduct) _buildVariantBadge(),
              if (_isEdit && _isVariantProduct) const SizedBox(height: 16),

              // ── Image ────────────────────────────────────────────────────────
              _buildImageSection(),
              const SizedBox(height: 20),

              TextFormField(
                controller: _skuController,
                decoration: InputDecoration(
                  labelText: 'SKU',
                  border: const OutlineInputBorder(),
                  suffixIcon: _skuGenerating
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.auto_awesome_rounded),
                          tooltip: 'Auto-generate unique SKU',
                          onPressed: _autoSKU,
                        ),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  border: const OutlineInputBorder(),
                  suffixIcon: _barcodeGenerating
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.qr_code_2_rounded),
                          tooltip: 'Auto-generate unique barcode',
                          onPressed: _autoBarcode,
                        ),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              // ── Category ─────────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: (_selectedCategoryId != null &&
                              _categories.any((c) => c['id'] == _selectedCategoryId))
                          ? _selectedCategoryId
                          : null,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                      items: _categories
                          .map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['name'])))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedCategoryId = val),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () async {
                      final name = await _showAddDialog('Category');
                      if (name != null && name.isNotEmpty) {
                        final newCat = await _commonService.createCategory(name);
                        setState(() {
                          _categories.add(newCat);
                          _selectedCategoryId = newCat['id'];
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Brand ─────────────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: (_selectedBrandId != null &&
                              _brands.any((b) => b['id'] == _selectedBrandId))
                          ? _selectedBrandId
                          : null,
                      decoration: const InputDecoration(labelText: 'Brand', border: OutlineInputBorder()),
                      items: _brands
                          .map((b) => DropdownMenuItem<int>(value: b['id'], child: Text(b['name'])))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedBrandId = val),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () async {
                      final name = await _showAddDialog('Brand');
                      if (name != null && name.isNotEmpty) {
                        final newBrand = await _commonService.createBrand(name);
                        setState(() {
                          _brands.add(newBrand);
                          _selectedBrandId = newBrand['id'];
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Unit ──────────────────────────────────────────────────────────
              // Every product should have a unit: it decides whether the till
              // will accept a fractional quantity for this product. Products
              // migrated from before units exist carry the default "Piece".
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: (_selectedUnitId != null &&
                              _units.any((u) => u.id == _selectedUnitId))
                          ? _selectedUnitId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                        helperText:
                            'Controls whether this product can be sold in decimal quantities.',
                      ),
                      items: _units
                          .map((u) => DropdownMenuItem<int>(
                                value: u.id,
                                child: Text(u.allowDecimal
                                    ? '${u.name} (decimals allowed)'
                                    : u.name),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedUnitId = val),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Manage units',
                    icon: const Icon(Icons.settings, color: Colors.blueGrey),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UnitsScreen(token: _token),
                        ),
                      );
                      // A unit may have been renamed, added or deleted while we
                      // were away, so reload rather than trusting the old list.
                      await _loadUnits();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Vendor ────────────────────────────────────────────────────────
              if (showReadOnlyVendor) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text('Vendor'),
                  subtitle: Text(effectiveVendorName),
                  trailing: const Icon(Icons.lock),
                ),
              ] else ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text('Vendor (optional)'),
                  subtitle: Text(_selectedVendor?['first_name']?.toString() ?? 'None selected'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedVendorId != null)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(() {
                            _selectedVendor   = null;
                            _selectedVendorId = null;
                          }),
                          icon: const Icon(Icons.clear),
                        ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.store),
                        label: Text(_selectedVendorId == null ? 'Pick' : 'Change'),
                        onPressed: _pickVendor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Stock & pricing ───────────────────────────────────────────────
              TextFormField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Opening Stock', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costPriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cost Price', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _wholesalePriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Wholesale Price', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tax Rate (%)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Tax Inclusive'),
                value: _taxInclusive,
                onChanged: (v) => setState(() => _taxInclusive = v),
              ),
              // Discount value + type toggle
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: _discountType == 'fixed'
                            ? 'Discount (Fixed Amount)'
                            : 'Discount (%)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Type toggle: % | Fixed
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      ToggleButtons(
                        isSelected: [
                          _discountType == 'percentage',
                          _discountType == 'fixed',
                        ],
                        onPressed: (idx) => setState(
                          () => _discountType = idx == 0 ? 'percentage' : 'fixed',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        children: const [
                          Tooltip(message: 'Percentage discount', child: Text('%', style: TextStyle(fontWeight: FontWeight.w700))),
                          Tooltip(message: 'Fixed amount discount', child: Text('Fx', style: TextStyle(fontWeight: FontWeight.w700))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        icon: Icon(_isEdit ? Icons.save : Icons.add),
                        label: Text(_isEdit ? 'Update Product' : 'Create Product'),
                        onPressed: _save,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
