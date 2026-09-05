import 'dart:io';
import 'package:enterprise_pos/api/common_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/unit_service.dart';
import 'package:enterprise_pos/models/product_unit.dart';
import 'package:enterprise_pos/models/product_packaging.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:enterprise_pos/widgets/reference_data_manager_dialog.dart';
import 'package:enterprise_pos/widgets/product_packaging_editor.dart';
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
  final _secondaryNameController  = TextEditingController();
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
  late UnitService   _unitService;

  /// Product-specific package conversions. Stock itself remains in the base unit.
  List<ProductPackaging> _packagings = [];

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
    _productService = ProductService(token: token);
    _commonService  = CommonService(token: token);
    _unitService    = UnitService(token: token);

    if (widget.product != null) {
      final p = widget.product!;
      _skuController.text            = p['sku']?.toString()     ?? '';
      _barcodeController.text        = p['barcode']?.toString() ?? '';
      _nameController.text           = p['name']?.toString() ?? '';
      _secondaryNameController.text  = p['secondary_name']?.toString() ?? '';
      _descController.text           = p['description']?.toString() ?? '';
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
      _packagings = ProductPackaging.listFromJson(p['packagings']);

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

    _priceController.addListener(_onPackageBasePriceChanged);
    _wholesalePriceController.addListener(_onPackageBasePriceChanged);
    _loadInitialData();
  }

  void _onPackageBasePriceChanged() {
    if (mounted && _packagings.isNotEmpty) setState(() {});
  }

  ProductUnit? get _selectedUnit {
    for (final unit in _units) {
      if (unit.id == _selectedUnitId) return unit;
    }
    final nested = widget.product?['unit'];
    if (nested is Map && (nested['id'] as num?)?.toInt() == _selectedUnitId) {
      return ProductUnit.fromJson(Map<String, dynamic>.from(nested));
    }
    return null;
  }

  bool get _hasPersistedPackaging => _packagings.any((p) => p.id != null);

  double get _baseRetailPrice => double.tryParse(_priceController.text.trim()) ?? 0;
  double get _baseWholesalePrice =>
      double.tryParse(_wholesalePriceController.text.trim()) ?? 0;


  /// Resolves a base unit when packaging is being added to an older/simple
  /// product that currently has no unit selected. We deliberately ask the
  /// user rather than silently assuming Piece because the base unit becomes
  /// the permanent conversion basis for Box/Carton/etc.
  Future<ProductUnit?> _requestBaseUnitForPackaging() async {
    final current = _selectedUnit;
    if (current != null) return current;

    if (_units.isEmpty) {
      await _loadUnits();
      if (!mounted) return null;
    }

    final choices = _units.where((u) => u.isActive).toList();
    if (choices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active units are available. Add or enable a unit first.'),
          ),
        );
      }
      return null;
    }

    int selectedId = (() {
      final piece = choices.where((u) => u.name.trim().toLowerCase() == 'piece');
      return piece.isNotEmpty ? piece.first.id : choices.first.id;
    })();

    final chosenId = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Select Base Unit'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Packaging must convert directly to the product base unit. '
                  'Choose the unit before adding Box, Carton, Pack, or other packaging.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: selectedId,
                  decoration: const InputDecoration(
                    labelText: 'Base Unit',
                    border: OutlineInputBorder(),
                  ),
                  items: choices
                      .map(
                        (u) => DropdownMenuItem<int>(
                          value: u.id,
                          child: Text(
                            u.allowDecimal
                                ? '${u.name} (decimals allowed)'
                                : u.name,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedId = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'Once saved with packaging, the base unit is protected from accidental changes.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedId),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (chosenId == null || !mounted) return null;

    ProductUnit? chosen;
    for (final unit in choices) {
      if (unit.id == chosenId) {
        chosen = unit;
        break;
      }
    }
    if (chosen == null) return null;

    setState(() => _selectedUnitId = chosen!.id);
    return chosen;
  }

  @override
  void dispose() {
    _priceController.removeListener(_onPackageBasePriceChanged);
    _wholesalePriceController.removeListener(_onPackageBasePriceChanged);
    _skuController.dispose();
    _barcodeController.dispose();
    _nameController.dispose();
    _secondaryNameController.dispose();
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
    // Load each reference list independently. A user can legitimately have
    // access to categories but not brands/units (or vice versa), and one 403
    // must never blank the other dropdowns.
    await Future.wait([
      _loadCategories(),
      _loadBrands(),
      _loadUnits(),
    ]);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _commonService.getCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  Future<void> _loadBrands() async {
    try {
      final brands = await _commonService.getBrands();
      if (!mounted) return;
      setState(() => _brands = brands);
    } catch (e) {
      debugPrint('Error loading brands: $e');
    }
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
        _units = units
            .where((u) => u.isActive || (_isEdit && u.id == _selectedUnitId))
            .toList();
        if (!_units.any((u) => u.id == _selectedUnitId)) {
          _selectedUnitId = null;
        }
        // Creating a product: default to Piece (when available) or the first
        // active unit. An inactive unit can remain visible only on an existing
        // product that already uses it.
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

  Future<void> _manageCategories() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-categories')) return;
    final result = await showNamedReferenceManagerDialog(
      context: context,
      title: 'Manage Categories',
      singularLabel: 'Category',
      icon: Icons.category_outlined,
      selectedId: _selectedCategoryId,
      loadItems: _commonService.getCategories,
      createItem: _commonService.createCategory,
      updateItem: _commonService.updateCategory,
      deleteItem: _commonService.deleteCategory,
    );
    if (result == null || !mounted) return;
    await _loadCategories();
    if (!mounted) return;
    setState(() {
      _selectedCategoryId = _categories.any((c) => c['id'] == result.selectedId)
          ? result.selectedId
          : null;
    });
  }

  Future<void> _manageBrands() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-brands')) return;
    final result = await showNamedReferenceManagerDialog(
      context: context,
      title: 'Manage Brands',
      singularLabel: 'Brand',
      icon: Icons.branding_watermark_outlined,
      selectedId: _selectedBrandId,
      loadItems: _commonService.getBrands,
      createItem: _commonService.createBrand,
      updateItem: _commonService.updateBrand,
      deleteItem: _commonService.deleteBrand,
    );
    if (result == null || !mounted) return;
    await _loadBrands();
    if (!mounted) return;
    setState(() {
      _selectedBrandId = _brands.any((b) => b['id'] == result.selectedId)
          ? result.selectedId
          : null;
    });
  }

  Future<void> _applyUnitChange(int? nextUnitId) async {
    if (nextUnitId == _selectedUnitId) return;
    if (_hasPersistedPackaging) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Base unit is locked because this product already has packaging conversions.',
          ),
        ),
      );
      return;
    }
    if (_packagings.isNotEmpty) {
      final clear = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Change base unit?'),
              content: const Text(
                'Packaging quantities are defined against the current base unit. Changing the unit will clear the unsaved packaging definitions so they cannot be reinterpreted incorrectly.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Clear Packaging & Change'),
                ),
              ],
            ),
          ) ??
          false;
      if (!clear || !mounted) return;
    }
    setState(() {
      _packagings = [];
      _selectedUnitId = nextUnitId;
    });
  }

  Future<void> _manageUnits() async {
    final auth = context.read<AuthProvider>();
    if (!auth.hasPermission('manage-units')) return;
    final result = await showUnitManagerDialog(
      context: context,
      service: _unitService,
      selectedId: _selectedUnitId,
      allowClearSelection: false,
    );
    if (result == null || !mounted) return;
    await _loadUnits();
    if (!mounted) return;
    if (result.selectedId != null &&
        _units.any((u) => u.id == result.selectedId)) {
      await _applyUnitChange(result.selectedId);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final payload = <String, dynamic>{
      'sku':             _skuController.text,
      'barcode':         _barcodeController.text,
      'name':            _nameController.text,
      'secondary_name':  _secondaryNameController.text.trim(),
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
      'packagings':      _packagings.map((p) => p.toJson()).toList(),
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
    final auth = context.watch<AuthProvider>();
    final canManageCategories = auth.hasPermission('manage-categories');
    final canManageBrands = auth.hasPermission('manage-brands');
    final canManageUnits = auth.hasPermission('manage-units');

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
                controller: _secondaryNameController,
                decoration: const InputDecoration(
                  labelText: 'Secondary Name',
                  hintText: 'Optional alternate or local-language name',
                  helperText: 'For example an Arabic, Urdu, or other local product name.',
                  border: OutlineInputBorder(),
                ),
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
                  if (canManageCategories)
                    IconButton(
                      tooltip: 'Manage categories',
                      icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                      onPressed: _loading ? null : _manageCategories,
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
                  if (canManageBrands)
                    IconButton(
                      tooltip: 'Manage brands',
                      icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                      onPressed: _loading ? null : _manageBrands,
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
                      decoration: InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                        helperText: _hasPersistedPackaging
                            ? 'Locked: packaging conversions already use this base unit.'
                            : 'Controls whether this product can be sold in decimal quantities.',
                      ),
                      items: _units
                          .map((u) => DropdownMenuItem<int>(
                                value: u.id,
                                child: Text(u.allowDecimal
                                    ? '${u.name} (decimals allowed)'
                                    : u.name),
                              ))
                          .toList(),
                      onChanged: _hasPersistedPackaging
                          ? null
                          : (val) => _applyUnitChange(val),
                    ),
                  ),
                  if (canManageUnits)
                    IconButton(
                      tooltip: 'Manage units',
                      icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                      onPressed: (_loading || _hasPersistedPackaging)
                          ? null
                          : _manageUnits,
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
              ProductPackagingEditor(
                packagings: _packagings,
                baseUnit: _selectedUnit,
                baseRetailPrice: _baseRetailPrice,
                baseWholesalePrice: _baseWholesalePrice,
                enabled: !_loading,
                onRequestBaseUnit: _requestBaseUnitForPackaging,
                onChanged: (items) => setState(() => _packagings = items),
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
